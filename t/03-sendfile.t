#!/usr/bin/env perl

use strict;
#use lib::abs '../blib/lib', '..';
use t::testlib;
use AnyEvent::HTTP::Server::Kit;

use Test::More;

my $file = __FILE__;
my $data = do { open my $f, '<', $file or die "$!"; local $/; <$f> };

our $PARTIAL;
sub ALL () { 1 }

test_server {
	my $s = shift;
	my $r = shift;
	diag "sending file $file";
	$r->sendfile(200, $file, headers => { 'content-type' => 'application/perl' });
	return;
}	'test1',
	[["GET /test1 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"], 200, { 'content-type' => 'application/perl' }, $data ],
if ALL;

done_testing();
