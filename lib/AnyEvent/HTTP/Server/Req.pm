package AnyEvent::HTTP::Server::Form;



package AnyEvent::HTTP::Server::Req;
{
package #hide
	aehts::sv;
use overload
	'""' => sub { ${$_[0]} },
	'@{}' => sub { [${$_[0]}] },
	fallback => 1;
package #hide
	aehts::av;
use overload
	'""' => sub { $_[0][0] },
	fallback => 1;
}

use AnyEvent::HTTP::Server::Kit;
	
	our @hdr = map { lc $_ }
	our @hdrn  = qw(Upgrade Connection Content-Type WebSocket-Origin WebSocket-Location Sec-WebSocket-Origin Sec-Websocket-Location Sec-WebSocket-Key Sec-WebSocket-Accept Sec-WebSocket-Protocol DataServiceVersion);
	our %hdr; @hdr{@hdr} = @hdrn;
	our %hdri; @hdri{ @hdr } = 0..$#hdr;
	our $LF = "\015\012";
	our $JSON;
	our $JSONP;
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
			my %h;
			while ( $_[1] =~ m{ \G ([^=]+) = ([^&]*) ( & | \Z ) }gcxso ) {
				my $k = url_unescape($1);
				my $v = bless do{\(my $o = url_unescape($2))}, 'aehts::sv';
				if (exists $h{$k}) {
					if (UNIVERSAL::isa($h{$k}, 'ARRAY')) {
						push @{$h{$k}},$v;
					} else {
						$h{$k} = bless [ $h{$k},$v ], 'aehts::av';
					}
				}
				else {
					$h{$k} = $v;
				}
			}
			return \%h;
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
		
		sub replyjs {
			my $self = shift;
			#warn "Replyjs: @_ by @{[ (caller)[1,2] ]}";
			my ($code,$data,%args);
			$code = ref $_[0] ? 200 : shift;
			$data = shift;
			%args = @_;
			$args{headers} ||= {};
			$args{headers}{'content-type'} ||= 'application/json';
			my $pretty = delete $args{pretty};
			$JSON or do {
				eval { require JSON::XS;1 }
					or do {
						warn "replyjs required JSON::XS, which could not be loaded: $@. Called from @{[ (caller)[1,2] ]}\n";
						$self->reply(500,'{error: "Internal Server Error" }', %args);
						return;
					};
				$JSON  = JSON::XS->new->utf8;
				$JSONP = JSON::XS->new->utf8->pretty;
			};
			my $jdata = eval {
				($pretty ? $JSONP : $JSON)->encode( $data );
			};
			defined $jdata or do {
				warn "Can't encode to JSON: $@ at @{[ (caller)[1,2] ]}\n";
				$self->reply(500,'{error: "Internal Server Error"}', %args);
				return;
			};
			$jdata =~ s{<}{\\u003c}sg;
			$jdata =~ s{>}{\\u003e}sg;
			$self->reply( $code, $jdata, %args );
			
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
			#return $self->headers(@_) if @_ % 2;
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
					$h->{'content-type'} .= '; charset=utf-8';
				}
			} else {
				$h->{'content-type'} = 'text/html; charset=utf-8';
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
			my $reply = "HTTP/1.1 $code $http{$code}$LF";
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
			#warn "send body part $length / ".length($content)."\n";
			$self->[3]->( \("$length$LF$content$LF") );
		}
		
		sub finish {
			my $self = shift;
			$self->[4] or die "Need to be chunked reply";
			#warn "send body end (".$self->connection.")\n";
			if( $self->[3] ) {
				$self->[3]->( \("0$LF$LF")  );
				$self->[3]->(\undef) if $self->connection eq 'close' or $self->[SERVER]{graceful};
				delete $self->[3];
				${ $self->[REQCOUNT] }--;
			}
		}

=head2 abort  - drop chunked connection

Let client know if an error occured by dropping connection before sending complete data

KNOWN ISSUES: nginx, when used as a reverse proxy, masks connection abort, leaving no 
ability for browser to detect error condition.

=cut
		sub abort {
			my $self = shift;
			$self->[4] or die "Need to be chunked reply";
			if( $self->[3] ) {
				$self->[3]->( \("1$LF"));
				$self->[3]->( \undef);
				delete $self->[3];
				${ $self->[REQCOUNT] }--;
			}
		}
		
		sub DESTROY {
			my $self = shift;
			#warn "Destroy req $self->[0] $self->[1] by @{[ (caller)[1,2] ]}";
			if( $self->[3] ) {
				if ($self->[4]) {
					$self->body(" response truncated");
					$self->abort();
				} else {
					$self->reply( 404, "Request not handled\n$self->[0] $self->[1]\n", headers => { 'content-type' => 'text/plain' } );
					#$self->[3]->(\("HTTP/1.0 404 Not Found\nConnection:close\nContent-type:text/plain\n\nRequest not handled\n"));
				}
			}
			@$self = ();
		}
