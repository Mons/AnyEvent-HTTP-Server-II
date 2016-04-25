#!/usr/bin/env perl

use strict;
use FindBin;
use lib "$FindBin::Bin/../blib/lib";
use Sys::Hostname;
use Getopt::Long;
use Cwd 'cwd','abs_path';
use AnyEvent::Handle;
use AnyEvent::HTTP::Server;
use File::Spec;
use EV;

my $host = hostname();

GetOptions(
	'p|port=s'   => \( my $port = 3080 ),
	'l|listen=s' => \( my $addr = '127.0.0.1' ),
);

my $path = abs_path(shift) // cwd();

warn "Serving $host ($addr:$port) ($path)\n";

my $s = AnyEvent::HTTP::Server->new(
	host => $addr,
	port => $port,
	cb => sub {
		my $r = shift;
		if ( $r->uri =~ m{^/ws} ) {
			if ($r->is_websocket) {
				return $r->upgrade(ping_interval => 0,sub {
					if (my $ws = shift) {
						warn 'websocket established';
						$ws->onmessage(sub {
							my $data = shift;
							warn("client message recv: $data");
						});
						$ws->onclose(sub {
							undef $ws;
							warn "websocket closed";
						});
					} else {
						warn "something wrong:$!";
						EV::unloop;
					}
				});
			}
			else {
				return $r->reply(400,'websocket headers required');
			}
		}
		else {
			return $r->reply(200,_get_html());
		}
	},
);
my ($h,$p) = $s->listen;
$s->accept;

warn "Started at http://$h:$p";
EV::loop;

sub _get_html {
<<HTML
<html>
	<head>
		<style type="text/css">
			table,tbody,tr,td {
				display: block;
				border: 0px;
				padding: 4px;
			}
		</style>
		<script language="javascript" type="text/javascript">
			var domain = "$h:$p";
			var socket;
			if (!socket) {
				socket = new WebSocket("ws://" + domain + "/ws");
				socket.onopen = function() {
					console.log("Socket established");
				}
				socket.onclose = function(event) {
					if (event.wasClean) {
						console.log("Socket closed");
					} else {
						console.log("Socket closed, unexected;Ev.code: " + event.code + " reason: " + event.reason);
					}
				};
				socket.onmessage = function(event) {
					console.log("Got data: " + event.data);
				};
				socket.onerror = function(error) {
					console.log("Error: " + error.message);
				};
			}
			function send_form_data() {
				var result = {};
				var elements = document.getElementById("myform").getElementsByTagName('input');
				for (var i=0; i < elements.length; i++) {
					if ( elements[i].type == 'text' ) {
						result[elements[i].name] = elements[i].value;
					}
				}
				var strdata = JSON.stringify(result);
				socket.send(strdata);
				//console.log("strdata="+strdata);
				return false;
			}
		</script>
	</head>
	<body>
		<form id="myform" onsubmit="event.preventDefault();return send_form_data(this);">
			<input type="text" name="msg" value="" />
			<input type="submit" />
		</form>
	</body>
</html>
HTML
}


1;
