package AnyEvent::HTTP::Server::WS;

use 5.010;
use AnyEvent::HTTP::Server::Kit;
#use Devel::Hexdump;
#use DDP;
use Config;
use Time::HiRes ();
use JSON::XS;
use Scalar::Util 'weaken';

BEGIN {
	unless (eval { require DDP;DDP->import(); 1}) {
		*p = sub { warn "no DDP for @_"; }
	}
}

our $JSON = JSON::XS->new->utf8;

sub time64 () {
	int( Time::HiRes::time() * 1e6 );
}

sub DEBUG () { 0 }

use constant {
	CONTINUATION => 0,
	TEXT         => 1,
	BINARY       => 2,
	CLOSE        => 8,
	PING         => 9,
	PONG         => 10,
	
	CONNECTING   => 1,
	OPEN         => 2,
	CLOSING      => 3,
	CLOSED       => 4,
};

our %OP = (
	CONTINUATION() => 'CONT',
	TEXT()         => 'TEXT',
	BINARY()       => 'BINR',
	CLOSE()        => 'CLOS',
	PING()         => 'PING',
	PONG()         => 'PONG',
);

sub onmessage {
	$_[0]{onmessage} = $_[1];
}

sub onerror {
	$_[0]{onerror} = $_[1];
}

sub onclose {
	$_[0]{onclose} = $_[1];
}


sub new {
	my $pkg = shift;
	my %args = @_;
	my $h = $args{h};
	my $self = bless {
		maxframe      => 1024*1024,
		mask          => 0,
		ping_interval => 5,
		state         => OPEN,
		%args,
	}, $pkg;
	
	$self->setup;
	return $self;
}

sub setup {
	my $self = shift;
	weaken($self);
	$self->{h}->on_read(sub {
		$self or return;
		#say "read".xd( $_[0]{rbuf} );
		while ( my $frame = $self->parse_frame( \$_[0]{rbuf} )) {
			p $frame;
			my $op = $frame->[4] || CONTINUATION;
			if ($op == PONG) {
				if ($self->{ping_id} == $frame->[5]) {
					my $now = time64();
					warn sprintf "Received pong for our ping. RTT: %0.6fs\n", ($now - $self->{ping_id})/1e6;
				} else {
					warn "Not our ping: $frame->[5]";
				}
				next;
			}
			elsif ($op == PING) {
				$self->send_frame(1, 0, 0, 0, PONG, $frame->[5]);
				next;
			}
			elsif ($op == CLOSE) {
				my ($code,$reason) = unpack 'na*', $frame->[5] if $frame->[5];
				
				$self->{onerror} && delete($self->{onerror})->($code,$reason) if $frame->[5];
				
				if ( $self->{state} == OPEN ) {
					# close was initiated by remote
					warn "close $code $reason";
					$self->send_frame(1,0,0,0,CLOSE,$frame->[5]);
					$self->{state} = CLOSED;
					$self->{onclose} && delete($self->{onclose})->({ clean => 1, code => $code, reason => $reason });
					$self->destroy;
					return;
				}
				elsif ( $self->{state} == CLOSING ) {
					# close was initiated by us
					$self->{close_cb} && delete($self->{close_cb})->();
					$self->{onclose} && delete($self->{onclose})->({ clean => 1, code => $code, reason => $reason });
					$self->destroy;
					return;
				}
				else {
					warn "close in wrong state";
				}
				
				$self->destroy;
				last;
			}
			
			
			# TODO: fin/!fin, continuation
			
			#if ( !$frame->[0] ) {
			#	# TODO: check summary size
			#	$self->{cont} .= $frame->[5];
			#	next;
			#}
			
			
			if ( $op == CONTINUATION ) {
				$self->{cont} .= $frame->[5];
				next;
			}
			
			my $data = ( delete $self->{cont} ).$frame->[5];
			if ($op == TEXT) {
				utf8::decode( $data );
			}
			$self->{onmessage} && $self->{onmessage}(
				$data,
				$op == TEXT ? 'text' : 'binary'
			);
		}
	});
	$self->{h}->on_error(sub {
		$self or return;
		warn "h error: @_";
		$self->{onerror} && delete($self->{onerror})->(0,$_[1]);
		$self->{onclose} && delete($self->{onclose})->({ clean => 0, data => $_[1] });
		$self->destroy;
	});
	$self->{pinger} = AE::timer 0,$self->{ping_interval}, sub {
		$self and $self->{h} or return;
		$self->{ping_id} = time64();
		$self->send_frame( 1,0,0,0, PING, $self->{ping_id});
	} if $self->{ping_interval} > 0;
	return;
}

sub destroy {
	my $self = shift;
	$self->{h} and (delete $self->{h})->destroy;
	#delete @{$self}{qw(onmessage onerror onclose)};
	#clean all except...
	%$self = (
		state => $self->{state}
	);
}


sub _xor_mask($$) {
	$_[0] ^
	(
		$_[1] x (length($_[0])/length($_[1]) )
		. substr($_[1],0,length($_[0]) % length($_[1]))
	);
}

sub parse_frame {
	my ($self,$rbuf) = @_;
	return if length $$rbuf < 2;
	my $clone = $$rbuf;
	#say "parsing frame: \n".xd "$clone";
	my $head = substr $clone, 0, 2;
	my $fin  = (vec($head, 0, 8) & 0b10000000) == 0b10000000 ? 1 : 0;
	my $rsv1 = (vec($head, 0, 8) & 0b01000000) == 0b01000000 ? 1 : 0;
	#warn "RSV1: $rsv1\n" if DEBUG;
	my $rsv2 = (vec($head, 0, 8) & 0b00100000) == 0b00100000 ? 1 : 0;
	#warn "RSV2: $rsv2\n" if DEBUG;
	my $rsv3 = (vec($head, 0, 8) & 0b00010000) == 0b00010000 ? 1 : 0;
	#warn "RSV3: $rsv3\n" if DEBUG;

	# Opcode
	my $op = vec($head, 0, 8) & 0b00001111;
	warn "OPCODE: $op ($OP{$op})\n" if DEBUG;
	
	# Length
	my $len = vec($head, 1, 8) & 0b01111111;
	warn "LENGTH: $len\n" if DEBUG;

	# No payload
	my $hlen = 2;
	if ($len == 0) { warn "NOTHING\n" if DEBUG }

	# Small payload
	elsif ($len < 126) { warn "SMALL\n" if DEBUG }

	# Extended payload (16bit)
	elsif ($len == 126) {
		return unless length $clone > 4;
		$hlen = 4;
		my $ext = substr $clone, 2, 2;
		$len = unpack 'n', $ext;
		warn "EXTENDED (16bit): $len\n" if DEBUG;
	}

	# Extended payload (64bit)
	elsif ($len == 127) {
		return unless length $clone > 10;
		$hlen = 10;
		my $ext = substr $clone, 2, 8;
		$len =
			$Config{ivsize} > 4
			? unpack('Q>', $ext)
			: unpack('N', substr($ext, 4, 4));
		warn "EXTENDED (64bit): $len\n" if DEBUG;
	}
	
	
	# TODO !!!
	# Check message size
	#$self->finish and return if $len > $self->{maxframe};
	

	# Check if whole packet has arrived
	my $masked = vec($head, 1, 8) & 0b10000000;
	return if length $clone < ($len + $hlen + ($masked ? 4 : 0));
	substr $clone, 0, $hlen, '';

	# Payload
	$len += 4 if $masked;
	return if length $clone < $len;
	my $payload = $len ? substr($clone, 0, $len, '') : '';

	# Unmask payload
	if ($masked) {
		warn "UNMASKING PAYLOAD\n" if DEBUG;
		my $mask = substr($payload, 0, 4, '');
		$payload = _xor_mask($payload, $mask);
		#say xd $payload;
	}
	warn "PAYLOAD: $payload\n" if DEBUG;
	$$rbuf = $clone;
	
	return [$fin, $rsv1, $rsv2, $rsv3, $op, $payload];
}

sub send_frame {
	my ($self, $fin, $rsv1, $rsv2, $rsv3, $op, $payload) = @_;
	$self->{h} or return warn "No handle for sending frame";
	warn "BUILDING FRAME\n" if DEBUG;
	
	# Head
	my $frame = 0b00000000;
	vec($frame, 0, 8) = $op | 0b10000000 if $fin;
	vec($frame, 0, 8) |= 0b01000000 if $rsv1;
	vec($frame, 0, 8) |= 0b00100000 if $rsv2;
	vec($frame, 0, 8) |= 0b00010000 if $rsv3;
	
	my $len = length $payload;
	# Mask payload
	warn "PAYLOAD: $payload\n" if DEBUG;
	my $masked = $self->{mask};
	if ($masked) {
		warn "MASKING PAYLOAD\n" if DEBUG;
		my $mask = pack 'N', int(rand( 2**32 ));
		$payload = $mask . _xor_mask($payload, $mask);
	}
	
	# Length
	#my $len = length $payload;
	#$len -= 4 if $self->{masked};
	
	# Empty prefix
	my $prefix = 0;
	
	# Small payload
	if ($len < 126) {
		vec($prefix, 0, 8) = $masked ? ($len | 0b10000000) : $len;
		$frame .= $prefix;
	}
	
	# Extended payload (16bit)
	elsif ($len < 65536) {
		vec($prefix, 0, 8) = $masked ? (126 | 0b10000000) : 126;
		$frame .= $prefix;
		$frame .= pack 'n', $len;
	}
	
	# Extended payload (64bit)
	else {
		vec($prefix, 0, 8) = $masked ? (127 | 0b10000000) : 127;
		$frame .= $prefix;
		$frame .=
			$Config{ivsize} > 4
			? pack('Q>', $len)
			: pack('NN', $len >> 32, $len & 0xFFFFFFFF);
	}
	
	if (DEBUG) {
		warn 'HEAD: ', unpack('B*', $frame), "\n";
		warn "OPCODE: $op\n";
	}
	
	# Payload
	$frame .= $payload;
	print "Built frame = \n".xd( "$frame" ) if DEBUG;
	
	$self->{h}->push_write( $frame );
	return;
}

sub send : method {
	my $self = shift;
	my $data = shift;
	my $is_text;
	if (ref $data) {
		$is_text = 1;
		$data = $JSON->encode($data);
	}
	elsif ( utf8::is_utf8($data) ) {
		if ( utf8::downgrade($data,1) ) {
		
		}
		else {
			$is_text = 1;
			utf8::encode($data);
		}
	}
	$self->send_frame(1, 0, 0, 0, ($is_text ? TEXT : BINARY ), $data);
}

sub close : method {
=for rem
   1000

      1000 indicates a normal closure, meaning that the purpose for
      which the connection was established has been fulfilled.
=cut
	my $self = shift;
	my $cb = pop;
	my $code = shift // 1000;
	my $msg = shift;
	if ($self->{state} == OPEN) {
		$self->send_frame(1,0,0,0,CLOSE,pack("na*",$code,$msg));
		$self->{state} = CLOSING;
		$self->{close_cb} = shift;
	}
	elsif ($self->{state} == CLOSING) {
		return;
	}
	elsif ($self->{state} == CLOSED) {
		warn "called close, while already closed from @{[ (caller)[1,2] ]}";
	}
	else {
		warn "close not possible in state $self->{state} from @{[ (caller)[1,2] ]}";
	}
}

sub DESTROY {
	my $self = shift;
	my $caller = "@{[ (caller)[1,2] ]}";
	if ($self->{h}) {
		warn "initiate close by DESTROY";
		my $copy = bless {%$self}, 'AnyEvent::HTTP::Server::WS::CLOSING';
		$copy->close(sub {
			warn "closed";
			undef $copy;
		});
	}
	warn "Destroy ws $self by $caller";
	%$self = ();
}

package AnyEvent::HTTP::Server::WS::CLOSING;

our @ISA = qw(AnyEvent::HTTP::Server::WS);

sub DESTROY {
	
}

1;
