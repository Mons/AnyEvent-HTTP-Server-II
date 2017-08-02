#!/usr/bin/env perl

use 5.010;
use strict;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../blib/lib";
use Getopt::Long;
use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::HTTP::Server;
use Async::Chain;
use File::Spec;
use EV;
use DDP;
use Data::Dumper;

my $s;$s = AnyEvent::HTTP::Server->new(
	debug_drop => 1,
	debug_conn => 1,
	host => 0,
	port => undef,
	on_reply => sub {
		p @_;
	},
	cb => sub {
		$s or return;
		return 200, "Meow!";
	},
);

my ($host,$port) = $s->listen;
$s->accept;


chain
sub {
	my $next = shift;
	tcp_connect $host,$port,sub {
		my $fh = shift or return warn "$!";
		my $h;$h = AnyEvent::Handle->new(
			fh       => $fh,
			on_error => sub { shift; warn "~~~ error: @_"; $h->destroy; $next->() },
			on_eof   => sub { shift; warn "~~~ eof"; $h->destroy; $next->() },
		);
		$h->push_write("GGG SS\0000\1\n\n\n");
		$h->on_read(sub{
			say delete $_[0]{rbuf};
		});
	};
},
sub {
	my $next = shift;
	tcp_connect $host,$port,sub {
		my $fh = shift or return warn "$!";
		my $h;$h = AnyEvent::Handle->new(
			fh       => $fh,
			on_error => sub { shift; warn "~~~ error: @_"; $h->destroy; $next->() },
			on_eof   => sub { shift; warn "~~~ eof"; $h->destroy; $next->() },
		);
		$h->push_write("GET / HTTP/1.1\nHost: asd.asd.asd.cc\nContent-type: ".("x"x(1024*128))."\n");
		$h->on_read(sub{
			say delete $_[0]{rbuf};
		});
	};
},
sub {
	my $next = shift;
	tcp_connect $host,$port,sub {
		my $fh = shift or return warn "$!";
		my $h;$h = AnyEvent::Handle->new(
			fh       => $fh,
			on_error => sub { shift; warn "~~~ error: @_"; $h->destroy; $next->() },
			on_eof   => sub { shift; warn "~~~ eof"; $h->destroy; $next->() },
		);
		$h->push_write("GET / HTTP/1.1\nHost: asd.asd.asd.cc\nBullshit\n\n");
		$h->on_read(sub{
			say delete $_[0]{rbuf};
		});
	};
},
sub {
	EV::unloop;
};

EV::loop;


1;
