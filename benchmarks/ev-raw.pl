#!/usr/bin/env perl

#use strict;
use EV;
#use AnyEvent::Impl::Perl;
use AnyEvent;
use AnyEvent::Socket;
#use Errno;

tcp_server 0, 8080, sub {
	binmode my $fh = shift, ':raw';
	my $rw;$rw = AE::io $fh, 0, sub {
		if ( sysread ( $fh, my $buf, 1024*40 ) > 0 ) {
			syswrite( $fh, "HTTP/1.1 200 OK\015\012Connection:close\015\012Content-Type:text/plain\015\012Content-Length:4\015\012\015\012Good" );
			undef $rw;
		}
		elsif ($! == Errno::EAGAIN) {
			return;
		}
		else {
			undef $rw;
		}
	};
};

#AnyEvent::Loop::run()
EV::loop;
