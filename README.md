# AnyEvent::HTTP::Server

*Fast HTTP/1.1 server component for AnyEvent Framework*

There is a previous implementation, that anybody could look to (http://github.com/Mons/AnyEvent-HTTP-Server), but it will never be on CPAN

If you just plan to use something for HTTP, better to look deeper into this version.

If you lack some functionality, please, open ticket or ask me. Maybe it could be easily added.

## Rationale

This module is a complete rewrite of previous version. Previous was not so slow, but It will slower than python's Twisted http server or node.js' http server. Also it was much slower than Twiggy.

Current implementation contains no XS and it is faster, than Twiggy with XS HTTP parser. Later I will enhance it with XS.

## Warning

*This is early development release. I'll try not to change interfaces in major, but some things may be a bit changed*

## Benchmarks

Benchmarking tool
	weighttp -c 100 -n 10000 http://localhost:8080/

Example app
	HTTP server on port 8080, which should reply with string "Good"

All files are located under benchmaks/

* AnyEvent::HTTP::Server-II (1 worker)

	finished in 1 sec, 295 millisec and 127 microsec, **7721** req/s, 912 kbyte/s
	

* AnyEvent::HTTP::Server-II ( **4** workers)

	finished in 0 sec, 552 millisec and 381 microsec, **18103** req/s, 2139 kbyte/s
	

* AnyEvent::HTTP::Server (previous)

	finished in 3 sec, 421 millisec and 143 microsec, **2922** req/s, 278 kbyte/s
	

* AnyEvent::HTTPD (v0.93t)

	finished in 18 sec, 622 millisec and 941 microsec, **536** req/s, 99 kbyte/s
	

* Twiggy (v0.1021)

	finished in 1 sec, 630 millisec and 908 microsec, **6131** req/s, 272 kbyte/s
	

* Starman (--workers 1) (v0.3006)

	finished in 2 sec, 469 millisec and 571 microsec, **4049** req/s, 511 kbyte/s
	

* Starman (--workers **4**) (best for my 4 core)

	finished in 1 sec, 102 millisec and 631 microsec, **9069** req/s, 1161 kbyte/s
	

* Pyton Twisted (I'm not a python programmer, so code may be not efficient)

	finished in 4 sec, 122 millisec and 587 microsec, **2425** req/s, 355 kbyte/s
	

* Node.js

	finished in 1 sec, 766 millisec and 696 microsec, **5660** req/s, 790 kbyte/s
	

* Nginx

		location / { perl 'use nginx; sub { $_[0]->send_http_header(q{text/plain}); $_[0]->print(q{Good}); return OK; }'; }
	
	finished in 0 sec, 290 millisec and 380 microsec, 34437 req/s, 5515 kbyte/s

* Raw TCP/HTTP server (perl+ev with no logic or parsing)

		For source look into benchmarks/ev-raw.pl
	
	finished in 0 sec, 306 millisec and 259 microsec, 32652 req/s, 2678 kbyte/s
