#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;
use System::Service;

plan tests => 1;

my $svc = System::Service->new();
ok $svc, "Created object";
is $svc->error, q{}, "No errors when created";

diag "Init system is ".$svc->{init};

exit 0;

