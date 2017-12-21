#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

# Note: use_ok() inside a BEGIN block does not work in some older Perl's, 
#   so we'll just call it direct
use_ok('Init::Service') || print "Bail out!\n";
diag("Testing Init::Service $Init::Service::VERSION, Perl $], $^X");
