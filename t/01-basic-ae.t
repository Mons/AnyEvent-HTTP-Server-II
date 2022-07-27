#use strict;
#use uni::perl ':dumper';

use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::HTTP::Server;
use AnyEvent::HTTP::Server::Kit ':dumper';
use AnyEvent::Loop;
use FindBin;

do "$FindBin::Bin/basic.pl" or die "$FindBin::Bin/basic.pl: ".($@ ? $@ : $!);
