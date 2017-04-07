#!/usr/bin/perl
use 5.006;
use strict;
use warnings;
use Test::More;
use System::Service;

plan tests => 69;

# All these tests require root (TODO: or an alternate file system root)
SKIP: {
    skip "*** These tests must be run as root", 69
        if $>;

    # Add & remove
    note "--- Create a dummy service ---";
    my $svc = System::Service->new();
    BAIL_OUT "Cannot create service: " . $svc->error
        if $svc->error;
    ok $svc, "Service object created";
    my $svc_nam = "test-020";
    my $svc_run = "/bin/sleep 5";
    my $svc_tit = "Test service for System::Service test #020";
    my $svc_typ = "simple";
    $svc->add(
        name    => $svc_nam,
        type    => $svc_typ,
        run => $svc_run,
        title   => $svc_tit
    );
    is $svc->error, q{}, "add() service status";
    is $svc->name(),    $svc_nam, "  Name correct";
    is $svc->run(), $svc_run, "  Run corect";
    is $svc->title(),   $svc_tit, "  Title correct";
    is $svc->type(),    $svc_typ, "  Type correct";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Load it back as a new object
    $svc = System::Service->new();    # make new object
    ok $svc, "Service object created for load";
    $svc->load($svc_nam);
    is $svc->error, q{}, "load() status";
    is $svc->name(),    $svc_nam, "  Name correct";
    is $svc->run(), $svc_run, "  Run corect";
    is $svc->title(),   $svc_tit, "  Title correct";
    is $svc->type(),    $svc_typ, "  Type correct";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Enable it for boot
    note " ";
    note "--- Enable boot of the dummy service ---";
    $svc->enable();
    is $svc->error, q{}, "enable() status";
    ok !$svc->running(), "  Not running";
    ok $svc->enabled(),  "  Is enabled for boot";

    # Reload, check if enabled
    $svc = System::Service->new();    # make new object
    ok $svc, "New object to check above";
    $svc->load($svc_nam);
    is $svc->error, q{}, "re-load() status";
    is $svc->name(),    $svc_nam, "  Name correct";
    is $svc->run(), $svc_run, "  Run corect";
    is $svc->title(),   $svc_tit, "  Title correct";
    is $svc->type(),    $svc_typ, "  Type correct";
    ok !$svc->running(), "  Not running";
    ok $svc->enabled(),  "  Is enabled for boot";

    # Disable from boot
    note " ";
    note "--- Disable boot of the dummy service ---";
    $svc->disable();
    is $svc->error, q{}, "disable() status";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Reload, check if disabled
    $svc = System::Service->new();    # make new object
    ok $svc, "New object to check above";
    $svc->load($svc_nam);
    is $svc->error, q{}, "  re-load() status";
    is $svc->name(),    $svc_nam, "  Name correct";
    is $svc->run(), $svc_run, "  Run corect";
    is $svc->title(),   $svc_tit, "  Title correct";
    is $svc->type(),    $svc_typ, "  Type correct";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Start it
    note " ";
    note "--- Start the dummy service ---";
    $svc->start();
    is $svc->error, q{}, "start() status";
    ok $svc->running(),  "  Is running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Reload, check if running
    $svc = System::Service->new();    # make new object
    ok $svc, "New object to check above";
    $svc->load($svc_nam);
    is $svc->error, q{}, "  re-load() status";
    is $svc->name(),    $svc_nam, "  Name correct";
    is $svc->run(), $svc_run, "  Run corect";
    is $svc->title(),   $svc_tit, "  Title correct";
    is $svc->type(),    $svc_typ, "  Type correct";
    ok $svc->running(),  "  Is running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Look for it on the system
    sleep 1;    # give it time to start, if system is busy
    my $out = qx(ps --no-header wax | /bin/grep -v grep | /bin/grep '$svc_run' 2>&1);
    isnt $out, q{}, "  Service found on system";

    # Stop it
    note " ";
    note "--- Stop the dummy service ---";
    $svc->stop();
    is $svc->error, q{}, "stop() status";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Reload, check if stopped
    $svc = System::Service->new();    # make new object
    ok $svc, "New object to check above";
    $svc->load($svc_nam);
    is $svc->error, q{}, "  re-load() status";
    is $svc->name(),    $svc_nam, "  Name correct";
    is $svc->run(), $svc_run, "  Run corect";
    is $svc->title(),   $svc_tit, "  Title correct";
    is $svc->type(),    $svc_typ, "  Type correct";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Remove it
    note " ";
    note "--- Remove the dummy service ---";
    $svc = System::Service->new();    # make new object
    ok $svc, "Service object created for remove";
    $svc->remove($svc_nam);
    is $svc->error, q{}, "Remove status OK";
    is $svc->name(),    q{}, "  Name ampty";
    is $svc->run(), q{}, "  run empty";
    is $svc->title(),   q{}, "  Title empty";
    is $svc->type(),    q{}, "  Type empty";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled";

}

exit 0;

