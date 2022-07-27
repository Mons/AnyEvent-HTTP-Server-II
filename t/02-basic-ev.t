#use strict;
#use uni::perl ':dumper';

use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::HTTP::Server;
use AnyEvent::HTTP::Server::Kit ':dumper';
use Test::More;
BEGIN{
    eval { require EV; 1 } or plan skip_all => "EV not installed";
}
use FindBin;

do "$FindBin::Bin/basic.pl" or die "$FindBin::Bin/basic.pl: $!";
