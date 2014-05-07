#!/usr/bin/env bash

MODULE=`perl -ne 'print($1),exit if m{version_from.+?([\w/.]+)}i' Makefile.PL`;
perl=perl
$perl -v

rm -rf MANIFEST.bak Makefile.old MYMETA.* META.* && \
pod2text $MODULE > README && \
$perl -i -lpne 's{^\s+$}{};s{^    ((?: {8})+)}{" "x(4+length($1)/2)}se;' README && \
AUTHOR=1 $perl Makefile.PL && \
make manifest && \
cp MYMETA.yml META.yml && \
cp MYMETA.json META.json && \
make && \
make disttest && \
make dist && \
cp -f *.tar.gz dist/ && \
make clean && \
cp META.yml MYMETA.yml && \
cp META.json MYMETA.json && \
rm -rf MANIFEST.bak Makefile.old && \
echo "All is OK"
