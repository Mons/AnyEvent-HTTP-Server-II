#!/usr/bin/env perl

use AnyEvent::HTTPD;
use EV;
my $server = AnyEvent::HTTPD->new( port => 8080 );
$server->reg_cb(
	'/' => sub {
		return$_[1]->respond({ content => ['text/html', "Good"] });
	},
);

$server->run;
EV::loop();
