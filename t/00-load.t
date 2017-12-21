#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

# Note: use_ok() doesn't work in Perl 5.8.8 inside a BEGIN block, so play some games...
BEGIN {
    if ($] != 5.008008) {
        use_ok('Init::Service') || print "Bail out!\n";
    };
}

if ($] == 5.008008) {
    use_ok('Init::Service') || print "Bail out!\n";
};

diag("Testing Init::Service $Init::Service::VERSION, Perl $], $^X");
