#!/usr/bin/env twiggy

# Run me as twiggy --listen :PORT psgi.pl

use strict;
use warnings;

use AnyEvent;
use Plack::Request;

# Ensure presence
use HTTP::Parser::XS;
use EV;

sub app {
    my $env = shift;

    my $req = Plack::Request->new($env);
    if ($req->path_info eq '/') {
        return sub {
            my $respond = shift;

            my $w = $respond->([200, ['Content-Type' => 'text/plain']]);
			$w->write("Good");
          }
    }

    [404, ['Content-Type' => 'text/plain'], ['Not found']];
}

\&app;
