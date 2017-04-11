#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok('Init::Service') || print "Bail out!\n";
}

diag("Testing Init::Service $Init::Service::VERSION, Perl $], $^X");
