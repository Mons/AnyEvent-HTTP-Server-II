#!/usr/bin/env perl

use FindBin;use lib "$FindBin::Bin/../blib/lib";
use AnyEvent::HTTP::Server;
use EV;
my $server = AnyEvent::HTTP::Server->new(
	cb => sub {
		return 200, "Good";
	},
);

$server->listen;

for (1..4) {
	my $pid = fork();
	if ($pid) {
		next;
	} else {
		last;
	}
}

$server->accept;
EV::loop();
