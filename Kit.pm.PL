#!/usr/bin/env perl


BEGIN{ 
	@ARGV or
		push @ARGV, do { my $x = $0; $x =~ s{\.PL$}{};$x };
}

my $package = $ARGV[0];
for ($package) {
	s{^(?:blib/|)lib/}{};
	s{\.pm$}{};
	s{/}{::}sg;
}


open STDOUT, ">$ARGV[0]~" or die "$ARGV[0]~: $!";


our $WARNS;
our $NOWARNS;
our $HINTS;
our %HINTS;

BEGIN {
	$HINTS = $^H;
	$WARNS = ${^WARNING_BITS};
	%HINTS = %^H;
}

use 5.008008;
use strict;

no  warnings;
BEGIN {
	$NOWARNS = ${^WARNING_BITS};
}

use warnings qw(FATAL closed threads internal debugging pack substr malloc
                unopened portable prototype inplace io pipe unpack regexp
                deprecated exiting glob digit printf utf8 layer
                reserved parenthesis taint closure semicolon);
no  warnings qw(exec newline);

BEGIN {
	if ($^V >= 5.011) {
		require feature;
		feature->import( qw(say state switch) );
		feature->unimport( qw(unicode_strings) );
	}
	elsif( $^V >= 5.090005 ) {
		require feature;
		feature->import( qw(say state switch) );
		require mro;
		mro->import('c3');
	}
	else {
		# no features (
	}
}

no utf8;
#use open qw(:raw);

#use utf8;
#use open qw(:utf8 :std);

BEGIN {
	$HINTS = $^H              & ~$HINTS;
	$WARNS = ${^WARNING_BITS} & ~( $WARNS || ("\0" x length ${^WARNING_BITS}) );
	my %h = %{^H};
	delete @h{ keys %HINTS };
	%HINTS = %h;
}

sub dumper($) {
	require Data::Dumper;
	my $s = Data::Dumper->new([@_])
			->Terse(1)
			->Indent(1)
			->Purity(0)
			->Useqq(1)
			->Quotekeys(0)
			->Dump;
	$s =~ s{\n+$}{}s;
	$s;
}

#printf "package #hide\n\t%s;\n\n", $package;
printf "package %s;\n\n", $package;

while (<DATA>) {
	if (/^SELFBEGIN/) {
		printf '	defined ${^WARNING_BITS}'."\n".
			'		?	${^WARNING_BITS} ^= ${^WARNING_BITS} ^ "%s"'."\n".
			'		:	${^WARNING_BITS} = "%s"'.";\n"
			,
			(join('', map "\\x$_", unpack "(H2)*", $WARNS))x2;
		printf "	\$^H |= 0x%x;\n\n", $HINTS;
		for (keys %HINTS) {
			print "	\$^H{'$_'} = ".dumper( $HINTS{$_}).";\n";
		}
	}
	elsif (/^IMPORT/) {
		print  "	# use warnings\n";
		printf '	${^WARNING_BITS} ^= ${^WARNING_BITS} ^ "%s";'."\n\n",
			join '', map "\\x$_", unpack "(H2)*", $WARNS;
		
		print  "	# use strict, utf8, open, 5.010, ...\n";
		printf "	\$^H |= 0x%x;\n\n", $HINTS;
		
		print  "	# use feature qw(@{[ keys %HINTS ]})\n";
		for (keys %HINTS) {
			print "	\$^H{'$_'} = ".dumper( $HINTS{$_}).";\n";
		}
		print "\n";
	}
	elsif (/^UNIMPORT/) {
		# TODO
		print  "	# no warnings\n";
		printf '	${^WARNING_BITS} = "%s";'."\n\n",
			join '', map "\\x$_", unpack "(H2)*", $NOWARNS;
		
		print  "	# no strict, ...\n";
		printf "	\$^H &= ~0x%x;\n\n", $HINTS;
		
		print  "	# no feature qw(@{[ keys %HINTS ]})\n";
		for (keys %HINTS) {
			print "	delete \$^H{'$_'};\n";
		}
		print "\n";
	}
	else {
		print;
	}
}

close STDOUT;
rename "$ARGV[0]~", $ARGV[0];

__DATA__

BEGIN {
SELFBEGIN
}
m{
use strict;
use warnings;
}x;

use Scalar::Util 'weaken', 'refaddr';

BEGIN {
	for my $sub (qw(carp croak confess)) {
		no strict 'refs';
		*$sub = sub {
			my $caller = caller;
			local *__ANON__ = $caller .'::'. $sub;
			require Carp;
			*{ $caller.'::'.$sub } = \&{ 'Carp::'.$sub };
			goto &{ 'Carp::'.$sub };
		};
	}
}

sub import {
	my $me = shift;
	my $caller = caller;
	local $^W;
IMPORT
	no strict 'refs';
	for my $sub (qw(carp croak confess)) {
		*{ $caller .'::'. $sub } = \&$sub;
	}
	return if $caller =~ /^$me/;
	while (@_) {
		my $feature = shift;
		if ($feature =~ s/^://) {
			if (defined &{ $feature }) {
				*{ $caller .'::'. $feature } = \&$feature;
			} else {
				croak "Unknown feature: :$feature";
			}
		}
	}
	return;
}

sub unimport {
	my $me = shift;
	my $caller = caller;
	local $^W;
UNIMPORT
	return;
}

sub xd ($;$) { no strict 'refs';
	if( eval{ require Devel::Hexdump; 1 }) { *{ caller().'::xd' } = \&Devel::Hexdump::xd; }
	else { *{ caller().'::xd' } = sub($;$) { my@a=unpack'(H2)*',$_[0];my$s='';
		$s .= "@a[ $_*16 .. $_*16 + 7 ]  @a[ $_*16+8 .. $_*16 + 15 ]\n" for (0..$#a/16);
		return $s;
	};}
	goto &{ caller().'::xd' };
}

sub dumper(@) {
	eval { require uni::dumper; 1} or goto &dumper_dd;
	no strict 'refs';
	*{ caller().'::dumper' } = \&uni::dumper::dumper;
	goto &{ caller().'::dumper' };
}

sub dumper_dd (@) {
	require Data::Dumper;
	no strict 'refs';
	*{ caller().'::dumper' } = sub (@) {
		my $s = Data::Dumper->new([@_])
			->Freezer('DUMPER_freeze')
			->Terse(1)
			->Indent(1)
			->Purity(0)
			->Useqq(1)
			->Quotekeys(0)
			->Dump;
		$s =~ s/\\x{([a-f0-9]{1,4})}/chr hex $1/sge;
		$s;
	};
	goto &{ caller().'::dumper' };
}

1;
