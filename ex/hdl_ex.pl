#!/usr/bin/env perl

use strict;
use FindBin;
use lib "$FindBin::Bin/../blib/lib";
use Getopt::Long;
use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::HTTP::Server;
use File::Spec;
use EV;

use Data::Dumper;

my $s;$s = AnyEvent::HTTP::Server->new(
	host => 0,
	port => undef,
	cb => sub {
		$s or return;
		my $r = $_[0];
		return HANDLE => sub {
			my $h = $_[0];
			$h->on_read(sub {
				#warn Dumper \@_;
				my $h = shift;
				warn "got message:<$h->{rbuf}>";
			});
		}
	},
);

my ($h,$p) = $s->listen;
$s->accept;

	tcp_connect $h,$p,sub {
		my $fh = shift or return warn "$!";
		my $h = AnyEvent::Handle->new( 
			fh       => $fh,
			on_error => sub { warn "error: @_" },
			on_eof   => sub { warn "error: @_" },
		);
		my $body = "GET /test1 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n";
		#warn 'written '.length($body).' bytes';
		$h->push_write($body);
		$h->push_write('test message');
	};

EV::loop;


1;
