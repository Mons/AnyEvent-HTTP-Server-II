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
$server->accept;
EV::loop();
