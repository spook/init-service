#!/usr/bin/perl
use 5.006;
use strict;
use warnings;
use Test::More;
use Init::Service;

my $NTESTS = 71;
plan tests => $NTESTS;

sub dq {    # de-quote for easier comparisons
    my $c = shift;
    $c =~ s{['"]+}{}mg;
    return $c;
}

# All these tests require root (TODO: or an alternate file system root)
SKIP: {
    skip "*** Test must run as root", $NTESTS
        if $>;

    # Make the daemon script
    note "--- Create dummy service A ---";
    my $svc_a_nam = "test-030-a";
    my $svc_a_dmn = "/tmp/$svc_a_nam.sh";
    my $svc_a_run = "$svc_a_dmn";
    my $svc_a_ttl = "Test Service 30 A";
    my $svc_a_typ = "simple";
    open D, ">", $svc_a_dmn
        or die "*** Cannot create daemon script $svc_a_dmn: $!";
    print D "#!/bin/sh\n";
    print D "sleep 5\n";
    print D "rm /var/run/$svc_a_nam.pid\n";
    print D "exit 0\n";
    close D;
    chmod 775, $svc_a_dmn
        or die "*** Cannot chmod() daemon script $svc_a_dmn: $!";
    ok 1, "Dummy daemon script A created";
    my $svc_a = Init::Service->new(
        name     => $svc_a_nam,
        type     => $svc_a_typ,
        runcmd   => $svc_a_run,
        title    => $svc_a_ttl,
    );
    BAIL_OUT "Cannot add service A to system: " . $svc_a->error if $svc_a->error;
    ok 1, "Service A added to system";

    note "--- Create dummy service B ---";
    my $svc_b_nam = "test-030-b";
    my $svc_b_dmn = "/tmp/$svc_b_nam.sh";
    my $svc_b_run = "$svc_b_dmn";
    my $svc_b_ttl = "Test Service 30 B";
    my $svc_b_typ = "simple";
    open D, ">", $svc_b_dmn
        or die "*** Cannot create daemon script $svc_b_dmn: $!";
    print D "#!/bin/sh\n";
    print D "sleep 5\n";
    print D "rm /var/run/$svc_b_nam.pid\n";
    print D "exit 0\n";
    close D;
    chmod 775, $svc_b_dmn
        or die "*** Cannot chmod() daemon script $svc_b_dmn: $!";
    ok 1, "Dummy daemon script B created";
    my $svc_b = Init::Service->new(
        name     => $svc_b_nam,
        type     => $svc_b_typ,
        runcmd   => $svc_b_run,
        title    => $svc_b_ttl,
        depends  => $svc_a_nam  # Depends on A  *** This is the thing we're testing ***
    );
    BAIL_OUT "Cannot add service B to system: " . $svc_b->error if $svc_b->error;
    ok 1, "Service A added to system";


    note "--- Given A and B are stopped, when I start A,";
    note "    then A is running and B remains stopped";
    # Given...
    is $svc_a->stop(), q{}, "  Reset A";
    is $svc_b->stop(), q{}, "  Reset B";
    # when...
    is $svc_a->start(), q{}, "  Start A";
    # then...
    is $svc_a->load(), q{}, "  Reload A";   # reload to be sure of status
    is $svc_b->load(), q{}, "  Reload B";   # reload to be sure of status
    ok $svc_a->running,  "  A is running";
    ok !$svc_b->running, "  B is not running";

    note "--- Given A and B are stopped, when I start B, ";
    note "    I get an error that A must be running first";
    # Given...
    is $svc_a->stop(), q{}, "  Reset A";
    is $svc_b->stop(), q{}, "  Reset B";
    # when...
    like $svc_b->start(), qr{error}, "  Tried to start B, get expected error";
    # then...
    is $svc_a->load(), q{}, "  Reload A";   # reload to be sure of status
    is $svc_b->load(), q{}, "  Reload B";   # reload to be sure of status
    ok !$svc_a->running, "  A is not running";
    ok !$svc_b->running, "  B is not running";


    note "--- Given A is running, when I start B, it starts normally";
    # Given...
    is $svc_a->stop(), q{}, "  Reset A";
    is $svc_b->stop(), q{}, "  Reset B";
    is $svc_a->start(), q{}, "  Start A";
    is $svc_a->load(), q{}, "  Reload A";   # reload to be sure of status
    is $svc_b->load(), q{}, "  Reload B";   # reload to be sure of status
    ok $svc_a->running,  "  A is running";
    ok !$svc_b->running, "  B is not running";
    # when...
    is $svc_b->start(), q{}, "  Start B";
    # then...
    is $svc_a->load(), q{}, "  Reload A";   # reload to be sure of status
    is $svc_b->load(), q{}, "  Reload B";   # reload to be sure of status
    ok $svc_a->running, "  A is running";
    ok $svc_b->running, "  B is running";

    note "--- Given A and B are running, when I stop B, ";
    note "    it stops normally and A continues";
    # Given...
    is $svc_a->stop(), q{}, "  Reset A";
    is $svc_b->stop(), q{}, "  Reset B";
    is $svc_a->start(), q{}, "  Start A";
    is $svc_b->start(), q{}, "  Start B";
    is $svc_a->load(), q{}, "  Reload A";   # reload to be sure of status
    is $svc_b->load(), q{}, "  Reload B";   # reload to be sure of status
    ok $svc_a->running, "  A is running";
    ok $svc_b->running, "  B is running";
    # when...
    is $svc_b->stop(), q{}, "  Stop B";
    # then...
    is $svc_a->load(), q{}, "  Reload A";   # reload to be sure of status
    is $svc_b->load(), q{}, "  Reload B";   # reload to be sure of status
    ok $svc_a->running,  "  A is running";
    ok !$svc_b->running, "  B is not running";

    note "--- Given A and B are running, when I stop A, ";
    note "    first B is stopped then A stops";
    # Given...
    is $svc_a->stop(), q{}, "  Reset A";
    is $svc_b->stop(), q{}, "  Reset B";
    is $svc_a->start(), q{}, "  Start A";
    is $svc_b->start(), q{}, "  Start B";
    is $svc_a->load(), q{}, "  Reload A";   # reload to be sure of status
    is $svc_b->load(), q{}, "  Reload B";   # reload to be sure of status
    ok $svc_a->running, "  A is running";
    ok $svc_b->running, "  B is running";
    # when...
    is $svc_a->stop(), q{}, "  Stop A";
    # then...
    is $svc_a->load(), q{}, "  Reload A";   # reload to be sure of status
    is $svc_b->load(), q{}, "  Reload B";   # reload to be sure of status
    ok !$svc_a->running, "  A is not running";
    ok !$svc_b->running, "  B is not running";

    note "--- Given A and B are running, when I kill A, ";
    note "    then B is stopped (except for SysVinit)";
    SKIP: {
        skip "Service monitoring not supported by SysV", 13
            if $svc_a->initsys eq Init::Service::INIT_SYSTEMV;

        # Given...
        is $svc_a->stop(), q{}, "  Reset A";
        is $svc_b->stop(), q{}, "  Reset B";
        is $svc_a->start(), q{}, "  Start A";
        is $svc_b->start(), q{}, "  Start B";
        is $svc_a->load(), q{}, "  Reload A";   # reload to be sure of status
        is $svc_b->load(), q{}, "  Reload B";   # reload to be sure of status
        ok $svc_a->running, "  A is running";
        ok $svc_b->running, "  B is running";
        # when...
        qx(killall -9 $svc_a_nam.sh);
        is $?, 0, "  Kill A";
        # then...
        is $svc_a->load(), q{}, "  Reload A";   # reload to be sure of status
        is $svc_b->load(), q{}, "  Reload B";   # reload to be sure of status
        ok !$svc_a->running, "  A is not running";
        ok !$svc_b->running, "  B is not running";
    }

    # Remove dummy services
    note "--- Cleanup ---";
    $svc_b->remove;
    unlink $svc_b_dmn;
    is $svc_b->error, q{}, "Service B removed";
    
    $svc_a->stop;
    $svc_a->remove;
    unlink $svc_a_dmn;
    is $svc_a->error, q{}, "Service A removed";
}

exit 0;
