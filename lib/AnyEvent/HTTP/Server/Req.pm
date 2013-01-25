package AnyEvent::HTTP::Server::Req;

use AnyEvent::HTTP::Server::Kit;
	
	our @hdr = map { lc $_ }
	our @hdrn  = qw(Upgrade Connection Content-Type WebSocket-Origin WebSocket-Location Sec-WebSocket-Origin Sec-Websocket-Location Sec-WebSocket-Key Sec-WebSocket-Accept Sec-WebSocket-Protocol);
	our %hdr; @hdr{@hdr} = @hdrn;
	our %hdri; @hdri{ @hdr } = 0..$#hdr;
	our $LF = "\015\012";
	our %http = do {
		local ($a,$b);
		my @w = qw(Content Entity Error Failed Found Gateway Large Proxy Request Required Timeout);
		map { ++$a;$b=0;map+(100*$a+$b++=>$_)x(!!$_),@$_; }
			["Continue","Switching Protocols","Processing",],
			[qw(OK Created Accepted),"Non-Authoritative Information","No $w[0]","Reset $w[0]","Partial $w[0]","Multi-Status",],
			["Multiple Choices","Moved Permanently","$w[4]","See Other","Not Modified","Use $w[7]",0,"Temporary Redirect",],
			["Bad $w[8]","Unauthorized","Payment $w[9]","Forbidden","Not $w[4]","Method Not Allowed","Not Acceptable","$w[7] Authentication $w[9]","$w[8] $w[10]","Conflict","Gone","Length $w[9]","Precondition $w[3]","$w[8] $w[1] Too $w[6]","$w[8]-URI Too $w[6]","Unsupported Media Type","$w[8] Range Not Satisfiable","Expectation $w[3]",(0)x4,"Unprocessable $w[1]","Locked","$w[3] Dependency","No code","Upgrade $w[9]",(0)x22,"Retry with",],
			["Internal Server $w[2]","Not Implemented","Bad $w[5]","Service Unavailable","$w[5] $w[10]","HTTP Version Not Supported","Variant Also Negotiates","Insufficient Storage",0,"Bandwidth Limit Exceeded","Not Extended",(0)x88,"Client $w[2]",],
	};
		
		use constant {
			METHOD    => 0,
			URI       => 1,
			HEADERS   => 2,
			WRITE     => 3,
			CHUNKED   => 4,
			PARSEDURI => 5,
			QUERY     => 6,
			REQCOUNT  => 7,
			SERVER    => 8,
		};
		
		sub connection { $_[0][2]{connection} =~ /^([^;]+)/ && lc( $1 ) }
		
		sub method  { $_[0][0] }
		sub full_uri { 'http://' . $_[0][2]{host} . $_[0][1] }
		sub uri     { $_[0][1] }
		sub headers { $_[0][2] }
		
		sub url_unescape($) {
			my $string = shift;
			$string =~ s/\+/ /sg;
			#return $string if index($string, '%') == -1;
			$string =~ s/%([[:xdigit:]]{2})/chr(hex($1))/ge;
			utf8::decode $string;
			return $string;
		}
		
		sub form {
			my $h = +{ map { my ($k,$v) = split /=/,$_,2; +( url_unescape($k) => url_unescape($v) ) } split /&/, $_[1] };
		}
		
		sub uri_parse {
			$_[0][5] = [
				$_[0][1] =~ m{ ^
					(?:
						(?:(?:([a-z]+):|)//|)
						([^/]+)
					|)
					(/[^?]*)
					(?:
						\? (.+|)
						|
					)
				$ }xso
			];
			$_[0][6] = +{ map { my ($k,$v) = split /=/,$_,2; +( url_unescape($k) => url_unescape($v) ) } split /&/, $_[0][5][3] };
		}
		
		sub path    {
			$_[0][5] or $_[0]->uri_parse;
			$_[0][5][2];
		}
		
		sub param {
			$_[0][6] or $_[0]->uri_parse;
			if ($_[1]) {
				return $_[0][6]{$_[1]};
			} else {
				return keys %{ $_[0][6] };
			}
		}
		
		sub sendfile {
			my $self = shift;
			my ( $code,$file,%args ) = @_;
			$code ||=200;
			my $reply = "HTTP/1.0 $code $http{$code}$LF";
			my $size = -s $file or $! and return warn "Can't sendfile `$file': $!";
			open my $f, '<:raw',$file or return  warn "Can't open file `$file': $!";
			
			my @good;my @bad;
			my $h = {
				server           => 'aehts-'.$AnyEvent::HTTP::Server::VERSION,
				%{ $args{headers} || {} },
				'connection' => ( $args{headers} && $args{headers}{connection} ) ? $args{headers}{connection} : $self->connection,
				'content-length' => $size,
			};
			if (exists $h->{'content-type'}) {
				if( $h->{'content-type'} !~ m{[^;]+;\s*charset\s*=}
				and $h->{'content-type'} =~ m{(?:^(?:text/|application/(?:json|(?:x-)?javascript))|\+(?:json|xml)\b)}i) {
					$h->{'content-type'} .= '; charset=UTF-8';
				}
			} else {
				$h->{'content-type'} = 'application/octet-stream';
			}
			for (keys %$h) {
				if (exists $hdr{lc $_}) { $good[ $hdri{lc $_} ] = $hdr{ lc $_ }.": ".$h->{$_}.$LF; }
				else { push @bad, "\u\L$_\E: ".$h->{$_}.$LF; }
			}
			defined() and $reply .= $_ for @good,@bad;
			$reply .= $LF;
			if( $self->[3] ) {
				$self->[3]->( \$reply );
				while ($size > 0) {
					my $l = sysread($f,my $buf,4096);
					defined $l or last;
					$size -= $l;
					$self->[3]->( \$buf );
				}
				$self->[3]->( \undef ) if $h->{connection} eq 'close' or $self->[SERVER]{graceful};
				delete $self->[3];
				${ $self->[REQCOUNT] }--;
			}
		}
		
		sub go {
			my $self = shift;
			my $location = shift;
			my %args = @_;
			( $args{headers} ||= {} )->{location} = $location;
			$self->reply( 302, "Moved", %args );
		}
		
		sub reply {
			my $self = shift;
			return $self->headers(@_) if @_ % 2;
			my ($code,$content,%args) = @_;
			$code ||=200;
			#if (ref $content) {
			#	if (ref $content eq 'HASH' and $content->{sendfile}) {
			#		$content->{size} = -s $content->{sendfile};
			#	}
			#	else {
			#		croak "Unknown type of content: $content";
			#	}
			#	
			#} else {
				utf8::encode $content if utf8::is_utf8 $content;
			#}
			my $reply = "HTTP/1.0 $code $http{$code}$LF";
			my @good;my @bad;
			my $h = {
				server           => 'aehts-'.$AnyEvent::HTTP::Server::VERSION,
				#'content-type+charset' => 'UTF-8';
				%{ $args{headers} || {} },
				#'connection' => 'close',
				'connection' => ( $args{headers} && $args{headers}{connection} ) ? $args{headers}{connection} : $self->connection,
				'content-length' => length($content),
			};
			if (exists $h->{'content-type'}) {
				if( $h->{'content-type'} !~ m{[^;]+;\s*charset\s*=}
				and $h->{'content-type'} =~ m{(?:^(?:text/|application/(?:json|(?:x-)?javascript))|\+(?:json|xml)\b)}i) {
					$h->{'content-type'} .= '; charset=UTF-8';
				}
			} else {
				$h->{'content-type'} = 'text/html; charset=UTF-8';
			}
			for (keys %$h) {
				if (exists $hdr{lc $_}) { $good[ $hdri{lc $_} ] = $hdr{ lc $_ }.": ".$h->{$_}.$LF; }
				else { push @bad, "\u\L$_\E: ".$h->{$_}.$LF; }
			}
			defined() and $reply .= $_ for @good,@bad;
			$reply .= $LF.$content;
			#if (!ref $content) { $reply .= $content }
			if( $self->[3] ) {
				$self->[3]->( \$reply );
				$self->[3]->( \undef ) if $h->{connection} eq 'close' or $self->[SERVER]{graceful};
				delete $self->[3];
				${ $self->[REQCOUNT] }--;
			}
		}
		
		sub send_headers {
			my ($self,$code,%args) = @_;
			$code ||= 200;
			my $reply = "HTTP/1.0 $code $http{$code}$LF";
			my @good;my @bad;
			my $h = {
				%{ $args{headers} || {} },
				#'connection' => 'close',
				#'connection' => 'keep-alive',
				'connection' => ( $args{headers} && $args{headers}{connection} ) ? $args{headers}{connection} : $self->connection,
			};
			if (!exists $h->{'content-length'}) { # TBD: and !connection->{upgrade}
				$h->{'transfer-encoding'} = 'chunked';
				$self->[4]= 1;
			}
			for (keys %$h) {
				if (exists $hdr{lc $_}) { $good[ $hdri{lc $_} ] = $hdr{ lc $_ }.": ".$h->{$_}.$LF; }
				else { push @bad, "\u\L$_\E: ".$h->{$_}.$LF; }
			}
			defined() and $reply .= $_ for @good,@bad;
			$reply .= $LF;
			#warn "send headers: $reply";
			$self->[3]->( \$reply );
		}
		
		sub body {
			my $self = shift;
			$self->[4] or die "Need to be chunked reply";
			my $content = shift;
			utf8::encode $content if utf8::is_utf8 $content;
			my $length = sprintf "%x", length $content;
			#warn "send body part $length\n$content\n";
			$self->[3]->( \("$length$LF$content$LF") );
		}
		
		sub finish {
			my $self = shift;
			$self->[4] or die "Need to be chunked reply";
			#warn "send body end\n";
			if( $self->[3] ) {
				$self->[3]->( \("0$LF")  );
				$self->[3]->(\undef) if $self->connection eq 'close' or $self->[SERVER]{graceful};
				delete $self->[3];
				${ $self->[REQCOUNT] }--;
			}
		}
		
		sub DESTROY {
			my $self = shift;
			#warn "Destroy req by @{[ (caller)[1,2] ]}";
			if( $self->[3] ) {
				if ($self->[4]) {
					$self->body(" response truncated");
					$self->finish();
				} else {
					$self->reply( 404, "Request not handled\n$self->[0] $self->[1]\n", headers => { 'content-type' => 'text/plain' } );
					#$self->[3]->(\("HTTP/1.0 404 Not Found\nConnection:close\nContent-type:text/plain\n\nRequest not handled\n"));
				}
			}
			@$self = ();
		}
