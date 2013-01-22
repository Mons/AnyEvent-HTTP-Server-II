#!/usr/bin/env perl

use Test::More tests => 1;

BEGIN {
    use_ok( 'AnyEvent::HTTP::Server' )
}

diag( "Testing AnyEvent::HTTP::Server $AnyEvent::HTTP::Server::VERSION, AnyEvent $AnyEvent::VERSION, Perl $], $^X" );
