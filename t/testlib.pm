package t::testlib;

use AnyEvent::HTTP::Server::Kit ':dumper';

use Test::More;
use AnyEvent::Socket;
use AnyEvent::Handle;

use AnyEvent::HTTP::Server;

our @EXPORT = qw(test_server test_server_close);
sub import { no strict 'refs';
	my $self = shift; my $caller = caller;
	defined &$_
		? *{ $caller.'::'.$_ } = \&$_
		: croak "$_ not exported by $self"
	for (@_ ? @_ : @EXPORT);
}

sub read_response {
	my $h = shift;
	my $cb = pop;
			my %h;
			delete $h->{_skip_drain_rbuf} if $h->{_eof};
			$h->push_read(line => sub {
				shift;
				diag "@_";
				$_[0] =~ /^HTTP\/([0-9\.]+) \s+ ([0-9]{3}) (?: \s+ ([^\015\012]*) )?/ixo
					or return $cb->( undef, "Invalid server response ($_[0])" );
				$h{''} = [ $1,$2,$3 ];
				
				my $hd;$hd = sub {
					$h->push_read(line => sub {
						shift;
						if ($_[0]) {
							#warn "got header @_";
							my ($k,$v) = split /\s*:\s*/,$_[0],2;
							$k = lc $k;
							$h{$k} = exists $h{$k} ? $h{$k}.';'.$v : $v;
							$hd->();
						} else {
							#warn "no more";
							if ( $h{ 'content-length' } ) {
								$h->push_read(chunk => $h{ 'content-length' }, sub {
									$h->on_error(sub { diag "Error '$_[2]' after reading response" });
									$cb->(\%h, $_[1]);
								});
							}
							elsif ($h{'transfer-encoding'} eq 'chunked') {
								my @chunks;
								my $reader;$reader = sub {
									$h->push_read(line => sub { shift;
										my $length = hex(shift);
										#warn "Chunk $length";
										if ($length) {
											$h->push_read( chunk => $length + 2, sub {
												shift;
												substr( $_[0], -2,2,"" ); # chomp CRLF
												#substr( $_[0], -1,1,"" ) if substr($_[0], -1,1) eq "\015"; # chomp CR
												push @chunks, $_[0];
												$reader->();
											} );
										} else {
											#warn dumper \@chunks;
											$h->push_read( chunk => 2, sub {
												$h->on_error(sub { diag "Error '$_[2]' after reading response" });
												$cb->(\%h,@chunks);
											});
										}
									});
								};
								$reader->();
							}
							else {
								$cb->(\%h);
							}
						}
					});
				};$hd->();
			});
}

sub send_request($@&) {
	my $h = shift;
	my $cb = pop;
	my @parts = @_;
	if (@parts == 1) {
		@parts = split //,$parts[0];
	}
	my $total = join '', @parts;
	diag substr($total, 0, index($total,"\n"));
	my $t;
	my $send;
	my $on_error = $h->{on_error};
	$h->on_error(sub{
		my $h = shift;
		undef $send;
		undef $t;
		if (not length $h->{rbuf}) {
			$h->destroy;
			$cb->({ Error => "$_[1]" });
			return;
		}
		$h->on_error($on_error);
		read_response($h,$cb);
	});
	if (!$::PARTIAL) {
		$h->push_write(join '', @parts);
		$h->on_error($on_error);
		read_response($h,$cb);
		return;
	}
	$send = sub {
		if (@parts) {
			$h->push_write(shift @parts);
			$t = AE::timer 0.0005,0,sub {
				return unless $send;
				undef $t;
				$send->();
			};
		} else {
			$h->on_error($on_error);
			read_response($h,$cb);
		}
	};
	$send->();
}

sub connect_handle($&) {
	my ($port,$cb) = @_;
	tcp_connect 0,$port, sub {
		my $fh = shift or return warn "$!";
		my $h = AnyEvent::Handle->new(
			fh => $fh,
			on_error => sub { warn "error: @_" },
			on_eof   => sub { warn "error: @_" },
			on_read  => sub { 1 },
		);
		$cb->($h);
	};
}

sub test_server (&@) {
	my $server_callback = shift;
	my ($opts,$name);
	while (@_ and ref $_[0] ne 'ARRAY') {
		if (ref $_[0] eq 'HASH') {
			$opts = shift;
		}
		elsif (!ref $_[0]) {
			$name = shift;
		}
		else {
			Carp::croak "Bad options";
		}
	}
	$name = ( $::PARTIAL ? 'partial' : 'complete' )." - $name";
	my @tests = @_;
	my $cv = AE::cv;
	my $s;$s = AnyEvent::HTTP::Server->new( %$opts, port => undef, cb => sub {
		$s or return;
		my $seq = ++$s->{__seq};
		my $r = $_[0];
		diag "request $seq. ".$r->method.' '.$r->uri;
		$server_callback->($s,@_);
	} );
	my ($host,$port) = $s->listen();
	$s->accept();
	
	connect_handle $port, sub {
		my $h = shift;
		my $idx = 0;
		my $rq;$rq = sub {
			return undef $h, $s->destroy, $cv->send unless @tests;
			++$idx;
			my ($req,$rescode,$resh,$resb, $morebody) = @{ shift @tests };
			#diag "send request:\n@$req";
			send_request( $h,@$req,sub {
				my $h = shift;
				my $b = join '', @_;
				#my ($h,$b) = @_;
				#diag explain \@_;
				is $h->{''}[1], $rescode, "$name $idx - reply status ok";
				is $h->{$_},$resh->{$_}, "$name $idx - reply header $_ ok" for (keys %$resh);
				if (UNIVERSAL::isa($resb, 'Regexp')) {
					like $b,$resb, "$name $idx - reply body like ok" or diag explain $h,$b;
				} else {
					is $b,$resb.$morebody, "$name $idx - reply body ok" or diag explain $h,$b, do {
						$Data::Dumper::Useqq=1;
						diag dumper $b;
						diag dumper $resb.$morebody;
					};
				}

				$rq->();
			});
		};
		$rq->();
	};
	$cv->recv;
}

sub test_server_close (&@) {
	my $server_callback = shift;
	my ($opts,$name);
	while (@_ and ref $_[0] ne 'ARRAY') {
		if (ref $_[0] eq 'HASH') {
			$opts = shift;
		}
		elsif (!ref $_[0]) {
			$name = shift;
		}
		else {
			Carp::croak "Bad options";
		}
	}
	my @tests = @_;
	my $cv = AE::cv;
	my $s;$s = AnyEvent::HTTP::Server->new( %$opts, port => undef, cb => sub {
		$s or return;
		my $seq = ++$s->{__seq};
		my $r = $_[0];
		diag "request $seq. ".$r->method.' '.$r->uri;
		$server_callback->($s,@_);
	} );
	my ($host,$port) = $s->listen();
	$s->accept();
	
	connect_handle $port, sub {
		my $h = shift;
		my $wait;
		my $end = sub {
			undef $h;
			$s->destroy;
			undef $wait;
			$cv->send;
		};
		
		$h->on_eof(sub {
			pass "$name - connection closed";
			$end->();
		});
		
		my $rq;$rq = sub {
			unless(@tests) {
				$h->on_read(sub {
					fail "$name - received unwaited data";
					diag $h->{rbuf};
					$end->();
				});
				$wait = AE::timer 1,0,sub {
					fail "$name - connection not closed";
					$end->();
				};
				return;
			};
			my ($req,$rescode,$resh,$resb, $morebody) = @{ shift @tests };
			#diag "send request:\n@$req";
			send_request( $h,@$req,sub {
				my $h = shift;
				my $b = join '', @_;
				#my ($h,$b) = @_;
				#diag explain \@_;
				is $h->{''}[1], $rescode, "$name - reply status ok";
				is $h->{$_},$resh->{$_}, "$name - reply header $_ ok" for (keys %$resh);
				is $b,$resb.$morebody, "$name - reply body ok" or diag explain $h,$b;
				$rq->();
			});
		};
		$rq->();
	};
	$cv->recv;
}
