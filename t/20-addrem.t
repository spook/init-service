#!/usr/bin/perl
use 5.006;
use strict;
use warnings;
use Test::More;
use System::Service;

plan tests => 11;

# All these tests require root (TODO: or an alternate file system root)
SKIP: {
    skip "*** These tests must be run as root", 11
        if $>;

    # Add & remove
    note "--- Create a dummy service ---";
    my $svc = System::Service->new();
    BAIL_OUT "Cannot create service: " . $svc->error
        if $svc->error;
    ok $svc, "Service object created";
    my $svc_nam = "test-020";
    my $svc_cmd = "/bin/sleep 21";
    my $svc_tit = "Test service for System::Service test #020";
    $svc->add(name => $svc_nam,
              command => $svc_cmd, 
              title => $svc_tit);
    is $svc->error, q{}, "Service added";
    # TODO check object's attributes match

    # Load it back
    $svc = System::Service->new();  # make new object
    ok $svc, "Service object created for load";
    $svc->load($svc_nam);
    is $svc->error, q{}, "Load status OK";
    is $svc->name(), $svc_nam, "Name correct";
    is $svc->command(), $svc_cmd, "Command correct";
    is $svc->title(), $svc_tit, "Title correct";
    ok !$svc->running(), "Not running";
    ok !$svc->enabled(), "Not enabled for boot";

    # Remove it
    note " ";
    note "--- Remove the dummy service ---";
    $svc = System::Service->new();  # make new object
    ok $svc, "Service object created for remove";
    $svc->remove($svc_nam);
    is $svc->error, q{}, "Remove status OK";
    # TODO: check for empty attributes


}




exit 0;

