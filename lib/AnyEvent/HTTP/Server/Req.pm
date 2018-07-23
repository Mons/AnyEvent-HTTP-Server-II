package AnyEvent::HTTP::Server::Form;

=head1 NAME

AnyEvent::HTTP::Server::Req - Request object used by AnyEvent::HTTP::Server

=head1 VERSION

Version 1.97

=cut

our $VERSION = '1.97';

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
use AnyEvent::HTTP::Server::WS;
use Time::HiRes qw/gettimeofday/;
use MIME::Base64 qw(encode_base64);
use Scalar::Util qw(weaken);
use Digest::SHA1 'sha1';

	our @hdr = map { lc $_ }
	our @hdrn  = qw(
		Access-Control-Allow-Credentials Access-Control-Allow-Origin Access-Control-Allow-Headers
		Upgrade Connection Content-Type WebSocket-Origin WebSocket-Location Sec-WebSocket-Origin Sec-Websocket-Location Sec-WebSocket-Key Sec-WebSocket-Accept Sec-WebSocket-Protocol DataServiceVersion);
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
			TIME      => 9,
			CTX       => 10,
			HANDLE    => 11,
			ATTRS     => 12,
		};
		
		sub connection { $_[0][2]{connection} =~ /^([^;]+)/ && lc( $1 ) }
		
		sub method  { $_[0][0] }
		sub full_uri { 'http://' . $_[0][2]{host} . $_[0][1] }
		sub uri     { $_[0][1] }
		sub headers { $_[0][2] }
		sub attrs   { $_[0][ATTRS] //= {} }
		sub server  { $_[0][SERVER] }

		sub replied {
			my $r = shift;
			if (@_) {
				$r->attrs->{replied} = shift;
			}
			else {
				$r->attrs->{replied};
			}
		}
		
		sub url_unescape($) {
			# return undef unless defined $_[0];
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
			# $_[0][5][2] = url_unescape( $_[0][5][2] );
			$_[0][6] = +{ map { my ($k,$v) = split /=/,$_,2; +( url_unescape($k) => url_unescape($v) ) } split /&/, $_[0][5][3] };
		}
		
		
		sub path    {
			$_[0][5] or $_[0]->uri_parse;
			$_[0][5][2];
		}
		
		sub query    {
			$_[0][5] or $_[0]->uri_parse;
			$_[0][5][3];
		}
		
		sub params {
			$_[0][6] or $_[0]->uri_parse;
			$_[0][6];
		}
		
		sub param {
			$_[0][6] or $_[0]->uri_parse;
			if ($_[1]) {
				return $_[0][6]{$_[1]};
			} else {
				return keys %{ $_[0][6] };
			}
		}
		our $CALLDEPTH = 1;
		
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
			my $callback_name = delete $args{jsonp_callback};
			!$callback_name or $callback_name =~ /^[a-zA-Z_][0-9a-zA-Z_]*$/ or do {
				warn "jsonp callbackname is invalid $callback_name. Called from @{[ (caller)[1,2] ]}\n";
				$self->reply(500,'{error: "Internal Server Error" }', %args);
				return;
			};
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
			$jdata = "$callback_name( $jdata );" if $callback_name;
			local $CALLDEPTH = $CALLDEPTH + 1;
			$self->reply( $code, $jdata, %args );
			
		}
		
		sub sendfile {
			my $self = shift;
			my ( $code,$file,%args ) = @_;
			$code ||=200;

			if ($self->replied) {
				warn "Double reply $code from ".join(":", (caller $CALLDEPTH)[1,2])." prev was from ".$self->replied."\n";
				exit 255 if $self->server->{exit_on_double_reply};
				return;
			}
			$self->replied(join ":", (caller $CALLDEPTH)[1,2]);

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
			local $CALLDEPTH = $CALLDEPTH + 1;
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
			};
			if ($self->method ne 'HEAD') {
				if ( exists $h->{'content-length'} ) {
					if ($h->{'content-length'} != length($content)) {
						warn "Content-Length mismatch: replied: $h->{'content-length'}, expected: ".length($content);
						$h->{'content-length'} = length($content);
					}
				} else {
					$h->{'content-length'} = length($content);
				}
			} else {
				if ( exists $h->{'content-length'} ) {
					# keep it
				}
				elsif(length $content) {
					$h->{'content-length'} = length $content;
				}
				else {
					$h->{'transfer-encoding'} = 'chunked';
				}
				$content = '';
			}
			if (exists $h->{'content-type'}) {
				if( $h->{'content-type'} !~ m{[^;]+;\s*charset\s*=}
				and $h->{'content-type'} =~ m{(?:^(?:text/|application/(?:json|(?:x-)?javascript))|\+(?:json|xml)\b)}i) {
					$h->{'content-type'} .= '; charset=utf-8';
				}
			} else {
				$h->{'content-type'} = 'text/html; charset=utf-8';
			}
			my $nh = delete $h->{NotHandled};

			# set multiple cookies
			if(ref $h->{'set-cookie'} eq 'ARRAY') {
				my $cookies = delete $h->{'set-cookie'};

				#set-cookie is not in @hdr
				push(@bad, "Set-Cookie: ".$_.$LF) for(@{$cookies});
			}

			for (keys %$h) {
				if (exists $hdr{lc $_}) { $good[ $hdri{lc $_} ] = $hdr{ lc $_ }.": ".$h->{$_}.$LF; }
				else { push @bad, "\u\L$_\E: ".$h->{$_}.$LF; }
			}
			defined() and $reply .= $_ for @good,@bad;
			# 2 is size of LF
			$self->attrs->{head_size} = length($reply) + 2;
			$self->attrs->{body_size} = length $content;
			$reply .= $LF.$content;
			#if (!ref $content) { $reply .= $content }
			if( $self->[3] ) {
				$self->[3]->( \$reply );
				$self->[3]->( \undef ) if $h->{connection} eq 'close' or $self->[SERVER]{graceful};
				delete $self->[3];
				${ $self->[REQCOUNT] }--;
			}
			if( $self->[8] && $self->[8]->{on_reply} ) {
				$h->{ResponseTime} = gettimeofday() - $self->[9];
				$h->{Status} = $code;
				$h->{NotHandled} = $nh if $nh;
				#eval {
					$self->[8]->{on_reply}->(
						$self,
						$h,
					);
				#1} or do {
				#	warn "on_reply died with $@";
				#};
			};

			if ($self->replied) {
				warn "Double reply $code from ".join(":", (caller $CALLDEPTH)[1,2])." prev was from ".$self->replied."\n";
				exit 255 if $self->server->{exit_on_double_reply};
				return;
			}
			$self->replied(join ":", (caller $CALLDEPTH)[1,2]);

			if( $self->[8] && $self->[8]->{stat_cb} ) {
				eval {
					$self->[8]->{stat_cb}->($self->path, $self->method, gettimeofday() - $self->[9]);
				1} or do {
					warn "stat_cb died with $@";
				}
			};
		}
		
		sub is_websocket {
			my $self = shift;
			return 1 if lc($self->headers->{connection}) eq 'upgrade' and lc( $self->headers->{upgrade} ) eq 'websocket';
			return 0;
		}
		
		sub upgrade {
			my $self = shift;
			#my %h;$h{h} = \%h; $h{r} = $self;
			
			my $cb = pop;
			my %args = @_;
			if ( $self->headers->{'sec-websocket-version'} == 13 ) {
				my $key = $self->headers->{'sec-websocket-key'};
				my $origin = exists $self->headers->{'sec-websocket-origin'} ? $self->headers->{'sec-websocket-origin'} : $self->headers->{'origin'};
				my $accept = encode_base64(sha1( $key . '258EAFA5-E914-47DA-95CA-C5AB0DC85B11' ));
				chomp $accept;
				$self->send_headers( 101,headers => {
					%{ $args{headers} || {} },
					upgrade => 'WebSocket',
					connection => 'Upgrade',
					'sec-websocket-accept' => $accept,
					#'sec-websocket-protocol' => 'chat',
				} );
				
				${ $self->[REQCOUNT] }--;
				
				my $create_ws = sub {
					my $h = shift;
					my $ws = AnyEvent::HTTP::Server::WS->new(
						%args, h => $h,
					);
					weaken( $self->[SERVER]{wss}{ 0+$ws } = $ws );
					@$self = ();
					$cb->($ws);
				};
				
				if ( $self->[HANDLE] ) {
					$create_ws->($self->[HANDLE]);
					return
				}
				else {
					return HANDLE => $create_ws
				}
			}
			else {
				$self->reply(400, '', headers => {
					'sec-websocket-version' => 13,
				});
			}
		}
		
		sub send_100_continue {
			my ($self,$code,%args) = @_;
			my $reply = "HTTP/1.1 100 $http{100}$LF$LF";
			$self->[3]->( \$reply );
		}

		sub send_headers {
			my ($self,$code,%args) = @_;
			$code ||= 200;

			if ($self->replied) {
				warn "Double reply $code from ".join(":", (caller $CALLDEPTH)[1,2])." prev was from ".$self->replied."\n";
				exit 255 if $self->server->{exit_on_double_reply};
				return;
			}
			$self->replied(join ":", (caller $CALLDEPTH)[1,2]);

			my $reply = "HTTP/1.1 $code $http{$code}$LF";
			my @good;my @bad;
			my $h = {
				%{ $args{headers} || {} },
				#'connection' => 'close',
				#'connection' => 'keep-alive',
				'connection' => ( $args{headers} && $args{headers}{connection} ) ? $args{headers}{connection} : $self->connection,
			};
			if (!exists $h->{'content-length'} and !exists $h->{upgrade}) {
				$h->{'transfer-encoding'} = 'chunked';
				$self->[4]= 1;
			} else {
				$self->[4]= 0;
			}
			for (keys %$h) {
				if (exists $hdr{lc $_}) { $good[ $hdri{lc $_} ] = $hdr{ lc $_ }.": ".$h->{$_}.$LF; }
				else { push @bad, "\u\L$_\E: ".$h->{$_}.$LF; }
			}
			defined() and $reply .= $_ for @good,@bad;
			$reply .= $LF;
			$h->{Status} = $code;
			$self->attrs->{sent_headers} = $h;
			$self->attrs->{head_size} = length $reply;
			$self->attrs->{body_size} = 0;
			#warn "send headers: $reply";
			$self->[3]->( \$reply );
			if (!$self->[4]) {
				if ($args{clearance}) {
					$self->[3] = undef;
				}
			}
		}
		
		sub body {
			my $self = shift;
			$self->[4] or die "Need to be chunked reply";
			my $content = shift;
			utf8::encode $content if utf8::is_utf8 $content;
			$self->attrs->{body_size} += length $content;
			my $length = sprintf "%x", length $content;
			#warn "send body part $length / ".length($content)."\n";
			$self->[3]->( \("$length$LF$content$LF") );
		}
		
		sub finish {
			my $self = shift;
			if ($self->[4]) {
				#warn "send body end (".$self->connection.")\n";
				if( $self->[3] ) {
					$self->[3]->( \("0$LF$LF")  );
					$self->[3]->(\undef) if $self->connection eq 'close' or $self->[SERVER]{graceful};
					delete $self->[3];
				}
				undef $self->[4];
			}
			elsif(defined $self->[4]) {
				undef $self->[4];
			}
			else {
				die "Need to be chunked reply";
			}
			${ $self->[REQCOUNT] }--;
			if ( $self->attrs->{sent_headers} ) {
				my $h = delete $self->attrs->{sent_headers};
				if( $self->[8] && $self->[8]->{on_reply} ) {
					$h->{ResponseTime} = gettimeofday() - $self->[9];
					$self->[8]->{on_reply}->(
						$self,
						$h,
					);
				};
			}
		}

		sub abort {
			my $self = shift;
			if( $self->[4] ) {
				if( $self->[3] ) {
					$self->[3]->( \("1$LF"));
					$self->[3]->( \undef);
					delete $self->[3];
				}
				undef $self->[4];
			}
			elsif (defined $self->[4]) {
				undef $self->[4];
			}
			else {
				die "Need to be chunked reply";
			}
			${ $self->[REQCOUNT] }--;
			if ( $self->attrs->{sent_headers} ) {
				my $h = delete $self->attrs->{sent_headers};
				if( $self->[8] && $self->[8]->{on_reply} ) {
					$h->{ResponseTime} = gettimeofday() - $self->[9];
					$h->{SentStatus} = $h->{Status};
					$h->{Status} = "590";
					$self->[8]->{on_reply}->(
						$self,
						$h,
					);
				};
			}
		}
		
		sub DESTROY {
			my $self = shift;
			my $caller = "@{[ (caller)[1,2] ]}";
			#warn "Destroy req $self->[0] $self->[1] by $caller";
			if( $self->[3] ) {
				local $@;
				eval {
					if ($self->[4]) {
						$self->abort();
					} else {
						if( $self->[8] && $self->[8]->{on_not_handled} ) {
							$self->[8]->{on_not_handled}->($self, $caller);
						}
						if ($self->[3]) {
							$self->reply( 500, "Request not handled\n$self->[0] $self->[1]\n", headers => { 'content-type' => 'text/plain', NotHandled => 1 } );
						}
					}
				1} or do {
					if ($EV::DIED) {
						@_ = ();
						goto &$EV::DIED;
					} else {
						warn "[E] Died in request DESTROY: $@ from $caller\n";
					}
				};
			}
			elsif (defined $self->[4]) {
				warn "[E] finish or abort was not called for ".( $self->[4] ? "chunked" : "partial" )." response";
				$self->abort;
			}
			@$self = ();
		}



1;

__END__


=head1 SYNOPSIS

    sub dispatch {
      my $request = shift;
      if ($request->path =~ m{ ^ /ping /? $}x) {
        $request->reply( 200, 'pong', headers=> { 'Content-Type' => 'text/plain'});
      } else {
        $request->reply( 404, 'Not found', headers=> { 'Content-Type' => 'text/plain'});
      }
    }

=head1 DESCRIPTION

  This module is a part of AnyEvent::HTTP::Server, see perldoc AnyEvent::HTTP::Server for details

=head1 EXPORT

  Does not export anything

=head1 SUBROUTINES/METHODS

=head2 connection  - 'Connection' header

  return Connection header from client request

=head2 method  - request method

  return HTTP Method been used in request, such as GET, PUT, HEAD, POST, etc..

=head2 full_uri  - URI with host part

  Requested uri with host and protocol name. Protocol part is always http://

=head2 uri  - URI aith host part stripped from it

  Requested uri without host and protocol name

=head2 headers - Headers from client request

  Return value is a hash reference. All header names are lowercased.

=head2 go($location) - Send redirect

  Redirect client to $location with 302 HTTP Status code.

=head2 reply($status,$content, $headers) - Send reply to client

  This method sends both headers and response body to client, and should be called at the end of
  request processing.

  Parameters:

=head3 status
    
    HTTP Status header (200 is OK, 403 is Auth required and so on).

=head3 content
    
    Response body as a scalar.

=head3 headers
    
    Response headers as a hash reference.

=head2 replyjs( [code], $data, %arguments ) - Send reply in JSON format

=head3 code
    
    Optional Status code, 200 is default.

=head3 data
    
    Response data to encode with JSON. All strings will be encoded as  UTF-8.

=head3 arguments
    
    List of key=> value arguments. The only supported argument for a moment is
    pretty => 1 | 0. JSON data will be formated for easier reading by human, 
    if pretty is true.

=head2 send_headers($code, @argumnets_list )  - send response headers to client

    This method may be used in conjunction with body() and finish() methods
    for streaming content serving. Response header 'transfer-encoding' is set 
    to 'chunked' by this method.

=head3 code
    
    HTTP Status code to send to a client.

=head3 arguments_list
    
    The rest of arguments is interpreted as a key=>value list. One should pass
    headers key, for example

    $request->send_headers(200, headers => { 'Content-type' => 'text/plain'} );

    Subsequent data should be send with body method, and after all data sent, finish 
    request handling with finish() method. Methods send_headers, body and finish 
    should be always used together.

=head2 body($data )  - send chunk of data to client

    Sends part ( or chunk ) of data to client

=head2 finish  - finish chunked request processing

    Finishes request by sending zero-length chunk to client.

=head2 abort  - drop chunked connection

  Let client know if an error occured by dropping connection before sending complete data

  KNOWN ISSUES: nginx, when used as a reverse proxy, masks connection abort, leaving no 
  ability for browser to detect error condition.

=cut


=head1 RESOURCES

=over 4

=item * GitHub repository

L<http://github.com/Mons/AnyEvent-HTTP-Server-II>

=back

=head1 ACKNOWLEDGEMENTS

=over 4

=item * Thanks to B<Marc Lehmann> for L<AnyEvent>

=item * Thanks to B<Robin Redeker> for L<AnyEvent::HTTPD>

=back

=head1 AUTHOR

Mons Anderson, <mons@cpan.org>

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

=cut
