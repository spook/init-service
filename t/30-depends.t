#!/usr/bin/perl
use 5.006;
use strict;
use warnings;
use Test::More;
use Init::Service;

my $NTESTS = 87;
plan tests => $NTESTS;

sub dq {    # de-quote for easier comparisons
    my $c = shift;
    $c =~ s{['"]+}{}mg;
    return $c;
}

# All these tests require root (TODO: or an alternate file system root)
SKIP: {
    skip "*** These tests must be run as root", $NTESTS
        if $>;

    # Make the daemon script
    diag "--- Create dummy service A ---";
    my $svc_a_nam = "test-030-a";
    my $svc_a_dmn = "/tmp/$svc_nam.sh";
    my $svc_a_run = "$svc_dmn";
    my $svc_a_ttl = "Test Service 30 A";
    my $svc_a_typ = "simple";
    open D, ">", $svc_a_dmn
        or die "*** Cannot create daemon script $svc_a_dmn: $!";
    print D "#!/bin/sh\n";
    print D "sleep 5\n";
    print D "rm /var/run/$svc_nam.pid\n";
    print D "exit 0\n";
    close D;
    chmod 775, $svc_a_dmn
        or die "*** Cannot chmod() daemon script $svc_a_dmn: $!";
    ok 1, "Dummy daemon script created";
    my $svc_a = Init::Service->new();
    ok $svc_a, "Service object created";
    is $svc_a->error, q{}, "  No error";
    $svc_a->add(
        name     => $svc_a_nam,
        type     => $svc_a_typ,
        runcmd   => $svc_a_run,
        title    => $svc_a_ttl,
    );

    diag "--- Create dummy service B ---";
    my $svc_b_nam = "test-030-b";
    my $svc_b_dmn = "/tmp/$svc_nam.sh";
    my $svc_b_run = "$svc_dmn";
    my $svc_b_ttl = "Test Service 30 B";
    my $svc_b_typ = "simple";
    open D, ">", $svc_b_dmn
        or die "*** Cannot create daemon script $svc_b_dmn: $!";
    print D "#!/bin/sh\n";
    print D "sleep 5\n";
    print D "rm /var/run/$svc_nam.pid\n";
    print D "exit 0\n";
    close D;
    chmod 775, $svc_b_dmn
        or die "*** Cannot chmod() daemon script $svc_b_dmn: $!";
    ok 1, "Dummy daemon script created";
    my $svc_b = Init::Service->new();
    ok $svc_b, "Service object created";
    is $svc_b->error, q{}, "  No error";
    $svc_b->add(
        name     => $svc_b_nam,
        type     => $svc_b_typ,
        runcmd   => $svc_b_run,
        title    => $svc_b_ttl,
#        depends  => $svc_a_nam  # Depends on A
    );


    # Remove dummy services
    $svc_b->stop;
    $svc_b->remove;
    unlink $svc_b_dmn;
    $svc_a->stop;
    $svc_a->remove;
    unlink $svc_a_dmn;
}

exit 0;

