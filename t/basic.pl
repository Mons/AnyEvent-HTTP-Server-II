#!/usr/bin/env perl

use Test::More tests => 224;
use Data::Dumper;
use FindBin;
use lib "$FindBin::Bin/..";
$Data::Dumper::Useqq = 1;

use t::testlib;

use constant {
	CHUNKED => 1,
	ALL     => 1,
};

our $PARTIAL;

my $bad = '\x'x1024;
my $bad_unescaped = 'x'x1024;

# The tests

for $PARTIAL (0, 1) {

test_server_close { return 200,'ok' } 'skip empty lines',
	[["\n\nGET /test1 HTTP/1.1\nHost:localhost\nConnection:close\n\n"], 200, { connection => 'close' }, 'ok' ],
if ALL;

test_server { return 200,'ok' } { max_header_size => 1024, read_size => 1024 }, 'reset too large',
	[["GET /test1 HTTP/1.1\nHost:" .("x"x2048). "\nConnection:keep-alive\n\n"], 413, { connection => 'close' }, qr/Request Entity Too Large/ ],
if ALL;

test_server { return 200,'ok' } 'reset bad request',
	[["GET /test1 HTTP/1\nHost:localhost\nConnection:keep-alive\n\n"], 400, { connection => 'close' }, qr/Bad Request/ ],
if ALL;

test_server {
	my $s = shift;
	my $r = shift;
	return (
		$r->method eq 'GET' ? 200 : 400,
		"$r->[0]:$r->[1]:$r->[2]{host}".$r->headers->{'x-t+q'},
		headers => {
			'content-type' => 'text/plain',
			'x-test' => $s->{__seq},
		},
	);
}	'immediate',
	[["GET /test1 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"],                          200, { 'x-test' => 1 }, "GET:/test1:localhost" ],
	[["GET /test2 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"],                          200, { 'x-test' => 2 }, "GET:/test2:localhost" ],
	[["METHOD /test3 HTTP/1.1\nHost:localhost\nConnection:keep-alive\nContent-Length:4\n\ntest"], 400, { 'x-test' => 3 }, "METHOD:/test3:localhost" ],
	[["GET /test4 HTTP/1.1\nHost:localhost\nConnection:keep-alive\nX-t: x; q=\"$bad\"\n\n"],      200, { 'x-test' => 4 }, "GET:/test4:localhost$bad_unescaped" ],
if ALL;

test_server {
	my $s = shift;
	my $r = shift;
	return (
		$r->method eq 'GET' ? 200 : 400,
		"$r->[0]:$r->[1]:$r->[2]{host}:".$r->headers->{accept}.':'.$r->headers->{'accept+q'},
		headers => {
			'content-type' => 'text/plain',
			'x-test' => $s->{__seq},
		},
	);
}	'by sub',
	[[qq{GET /test1 HTTP/1.1\nHost:localhost\nConnection:keep-alive\nAccept:*/*\n\t;q="\\"1\\"!=2"\n\n}],     200, { 'x-test' => 1 }, q{GET:/test1:localhost:*/* ;q="\"1\"!=2":"1"!=2} ], # "
	[[qq{GET /test2 HTTP/1.1\nHost:localhost\nConnection:keep-alive\nAccept:*/*; q="1\\!=2"\n\n}],            200, { 'x-test' => 2 }, q{GET:/test2:localhost:*/*; q="1\\!=2":1!=2} ], # "
	[[qq{GET /test3 HTTP/1.1\nHost:localhost\nConnection:keep-alive\nAccept:*/*; q="1\n\t2"\n\n}],            200, { 'x-test' => 3 }, q{GET:/test3:localhost:*/*; q="1 2":1 2} ], # "
	[[qq{GET /test4 HTTP/1.1\nHost:localhost\nConnection:keep-alive\nAccept:*/*;\n\t q="1 2"\n\n}],           200, { 'x-test' => 4 }, q{GET:/test4:localhost:*/*; q="1 2":1 2} ], # "
	[["GET /test5 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"],                                      200, { 'x-test' => 5 }, "GET:/test5:localhost::" ],
	[["METHOD /test6 HTTP/1.1\nHost:localhost\nConnection:keep-alive\nContent-Length:4\n\ntest"],             400, { 'x-test' => 6 }, "METHOD:/test6:localhost::" ],
	[[qq{GET /test1 HTTP/1.1\nHost:localhost\nConnection:keep-alive\nAccept:*/*\n\t;q=123\n\n}],              200, { 'x-test' => 7 }, q{GET:/test1:localhost:*/* ;q=123:123} ], # "
	[[qq{GET /test7 HTTP/1.1\nHost:localhost\nConnection:keep-alive\nAccept:*/*;\n\t q="$bad"\n\n}],          200, { 'x-test' => 8 }, qq{GET:/test7:localhost:*/*; q="$bad":$bad_unescaped} ], # "
if ALL;

test_server {
	my $s = shift;
	my $r = shift;
	my $replybody = "$r->[0]:$r->[1]:$r->[2]{host}";
	return sub {
		my ($last,$body) = @_;
		#diag explain "$last:$body";
		if ($body) {
			$replybody .= ':'.length($$body).':'.$$body;
		}
		if ($last) {
			$r->reply(
				$r->method eq 'GET' ? 200 : 400,
				$replybody,
				headers => {
					'content-type' => 'text/plain',
					'x-test' => $s->{__seq},
				},
			);
		}
	}
}	'read body',
	[["GET /test1 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"],                          200, { 'x-test' => 1 }, "GET:/test1:localhost:0:",'' ],
	[["GET /test2 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"],                          200, { 'x-test' => 2 }, "GET:/test2:localhost:0:",'' ],
	[["METHOD /test3 HTTP/1.1\nHost:localhost\nConnection:keep-alive\nContent-Length:4\n\ntest"], 400, { 'x-test' => 3 }, "METHOD:/test3:localhost", $PARTIAL ? ":1:t:1:e:1:s:1:t" : ':4:test' ],
if ALL;


test_server {
	my $s = shift;
	my $r = shift;
	my $replybody = "$r->[0]:$r->[1]:$r->[2]{host}";
	my @reply = split //, $replybody;
	my $t;$t = AE::timer 0,0.01, sub {
		if (@reply) {
			$r->body(shift @reply);
		} else {
			undef $t;
			$r->finish;
		}
	};
	$r->send_headers(
		$r->method eq 'GET' ? 200 : 400,
		headers => {
			'content-type' => 'text/plain',
			'x-test' => $s->{__seq},
		},
	);
	return;
}	'chunked',
	[["GET /test1 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"],                          200, { 'x-test' => 1 }, "GET:/test1:localhost",'' ],
	[["GET /test2 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"],                          200, { 'x-test' => 2 }, "GET:/test2:localhost",'' ],
	[["METHOD /test3 HTTP/1.1\nHost:localhost\nConnection:keep-alive\nContent-Length:4\n\ntest"], 400, { 'x-test' => 3 }, "METHOD:/test3:localhost", '' ],
if ALL or CHUNKED;


test_server {
	my $s = shift;
	my $r = shift;
	my $replybody = "$r->[0]:$r->[2]{host}:".$r->path.':'.$r->param("query").':'.join(',',sort $r->param);
	return (
		200,
		$replybody
	);
}	'query',
	[["GET /test1?query=10+1 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"],                          200,{}, "GET:localhost:/test1:10 1:query",'' ],
	[["GET https://test:80/test2/3?query=10%201 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"],       200,{}, "GET:localhost:/test2/3:10 1:query",'' ],
	[["GET //test/test3?query= HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"],                        200,{}, "GET:localhost:/test3::query",'' ],
	[["GET /test4?a=%20&b=%25 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"],                         200,{}, "GET:localhost:/test4::a,b",'' ],
if ALL;

my $formdata = "a=%20&b=%25";
my $LF = "\015\012";
my $mpart = q{
--Test
Content-Disposition: form-data; name="Part1"; key="MyKey"

Part1Content
--Test
Content-Disposition: form-data; name="Part2"
Content-Transfer-Encoding: quoted-printable

=?UTF-8?Q?=74=65=73=74?=
--Test
Content-Disposition: form-data; name="Part3";
	filename="some-image.jpg"
Content-Type: image/jpeg
Content-Transfer-Encoding: base64

dGVzdA==
--Test
};

=for
=cut

( my $mpart2 = $mpart ) =~ s{\015?\012}{\015\012}sg;

test_server {
	my $s = shift;
	my $r = shift;
	my $replybody = $r->method.':'.$r->path;
	# form-data
	# form-url
	# raw
	my $rr = $r;
	return {
		raw => sub {
			warn "raw: ".explain \@_;
			$r->reply(
				200,
				$replybody
			);
		},
		multipart => sub {
			my ($last,$part,$hd) = @_;
			$rr;
			#warn Dumper $part, $hd;
			#diag explain $hd;
			$replybody .= ':'.( utf8::is_utf8($part) ? 'u' : 'a' );
			utf8::encode($part) if utf8::is_utf8($part);
			$replybody .= ':'.$hd->{name}.':'.$hd->{filename}.':'.$part;
			if ($last) {
				$r->reply(
					200,
					$replybody
				);
			};
		},
		form => sub {
			my ($form,$rawbody) = @_;
			$r->reply(
				200,
				$r->method.':'.$r->path.':'.join('&', map { $_.'='.$form->{$_} } sort keys %$form )
			);
			#diag explain \@_;
		},
	};
}	'multipart',
	[["POST /test1?query=10+1 HTTP/1.1\nHost:localhost\nContent-type:application/x-www-form-urlencoded\nConnection:keep-alive\nContent-Length:".length($formdata)."\n\n$formdata"],
		200, {}, "POST:/test1:a= &b=%",'' ],
	[["POST /test2 HTTP/1.1\nHost:localhost\nContent-type:multipart/form-data; boundary=Test\nConnection:keep-alive\nContent-Length:".length($mpart)."\n\n$mpart"],
		200, {}, "POST:/test2:a:Part1::Part1Content:u:Part2::test:a:Part3:some-image.jpg:test",'' ],
	[[qq{POST /test2 HTTP/1.1\nHost:localhost\nContent-type:multipart/form-data; boundary="Test"\nConnection:keep-alive\nContent-Length:}.length($mpart)."\n\n$mpart"],
		200, {}, "POST:/test2:a:Part1::Part1Content:u:Part2::test:a:Part3:some-image.jpg:test",'' ],
	[["POST /test2 HTTP/1.1\nHost:localhost\nContent-type:multipart/form-data; boundary=Test\nConnection:keep-alive\nContent-Length:".length($mpart2)."\n\n$mpart2"],
		200, {}, "POST:/test2:a:Part1::Part1Content:u:Part2::test:a:Part3:some-image.jpg:test",'' ],
	[[qq{POST /test2 HTTP/1.1\nHost:localhost\nContent-type:multipart/form-data; boundary="Test"\nConnection:keep-alive\nContent-Length:}.length($mpart2)."\n\n$mpart2"],
		200, {}, "POST:/test2:a:Part1::Part1Content:u:Part2::test:a:Part3:some-image.jpg:test",'' ],
#	[["GET /test HTTP/1.1\nConnection:close\n\n"], 200,{}, "GET:/test",'' ],
#	[["GET /test HTTP/1.1\nConnection:close\n\n"], 200,{}, "GET:/test",'' ],
if ALL;

#(
#	qq{Header: test\n\t;\n\tfield=value},
#	qq{Header: test;\n field1="value1 +"\n ;field2=\n    value2},
#)

test_server {
	my $s = shift;
	my $r = shift;
	return;
}	'overlap',
	[["GET /test1 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"],                          500, {}, "Request not handled\nGET /test1\n" ],
	[["GET /test2 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\nGET"],                       500, {}, "Request not handled\nGET /test2\n" ],
	[[" /test3 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"],                             500, {}, "Request not handled\nGET /test3\n" ],
	[["POST /test4 HTTP/1.1\nHost:localhost\nConnection:keep-alive\nContent-Length:4\n\ntestPOST"], 500, {}, "Request not handled\nPOST /test4\n",'' ],
	[[" /test5 HTTP/1.1\nHost:localhost\nConnection:keep-alive\nContent-Length:4\n\ntest"],        500, {}, "Request not handled\nPOST /test5\n",'' ],
	[["POST /test6 HTTP/1.1\nHost:localhost\nConnection:keep-alive\nContent-Length:4\n\nte","st"], 500, {}, "Request not handled\nPOST /test6\n",'' ],
#	[["GET /test2 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"],                          200, { 'x-test' => 2 }, "GET:/test2:localhost" ],
#	[["METHOD /test3 HTTP/1.1\nHost:localhost\nConnection:keep-alive\nContent-Length:4\n\ntest"], 400, { 'x-test' => 3 }, "METHOD:/test3:localhost" ],
if ALL;

test_server_close {
	my $s = shift;
	my $r = shift;
	return;
}	'connection close',
	[["GET /test1 HTTP/1.1\nHost:localhost\nConnection:close\n\n"],                          500, {}, "Request not handled\nGET /test1\n" ],
if ALL;

test_server {
	return 204, undef, headers => {};
}	'204 - no cl - undef',
	[["GET /test1 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"], 204, { 'content-length' => undef }, "" ],
if ALL;

test_server {
	return 204, "", headers => {};
}	'204 - no cl - empty',
	[["GET /test1 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"], 204, { 'content-length' => undef }, "" ],
if ALL;

test_server {
	my $s = shift;
	my $r = shift;
	return 204, "some content", headers => {};
}	'204 - with content',
	[["GET /test1 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"], 204, { 'content-length' => undef }, "" ],
if ALL;

test_server {
	my $s = shift;
	my $r = shift;
	return 204, "", headers => {'content-length' => 0};
}	'204 - with header',
	[["GET /test1 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"], 204, { 'content-length' => undef }, "" ],
if ALL;

test_server {
	my $s = shift;
	my $r = shift;
	return 200, undef;
}	'200 - with undef body',
	[["GET /test1 HTTP/1.1\nHost:localhost\nConnection:keep-alive\n\n"], 200, { 'content-length' => 0 }, "" ],
if ALL;

}

done_testing();
