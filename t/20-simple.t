#!/usr/bin/perl
use 5.006;
use strict;
use warnings;
use Test::More;
use Init::Service;

plan tests => 85;

# All these tests require root (TODO: or an alternate file system root)
SKIP: {
    skip "*** These tests must be run as root", 85
        if $>;

    # Make the daemon script
    diag "--- Create a dummy daemon ---";
    my $svc_nam = "test-020";
    my $svc_pre = "/bin/true 1 2 3";
    my $svc_exe = "/tmp/$svc_nam.sh";
    my $svc_run = "$svc_exe a b c";
    my $svc_pos = "/bin/true 99";
    my $svc_tit = "Test service for Init::Service test #020";
    my $svc_typ = "simple";
    open D, ">", $svc_exe
        or die "*** Cannot create daemon script $svc_exe: $!";
    print D "#!/bin/sh\n";
    print D "echo \$\$ > /var/run/$svc_nam.pid\n";
    print D "sleep 1\n";
    print D "echo Got \$*\n";
    print D "sleep 5\n";
    print D "rm /var/run/$svc_nam.pid\n";
    print D "exit 0\n";
    close D;
    chmod 775, $svc_exe
        or die "*** Cannot chmod() daemon script $svc_exe: $!";
    ok 1, "Dummy daemon script created";

    # Add & remove
    diag " ";
    diag "--- new() the dummy service ---";
    my $svc = Init::Service->new();
    ok $svc, "Service object created";
    is $svc->error, q{}, "  No error";
    $svc->add(
        name    => $svc_nam,
        type    => $svc_typ,
        prerun  => $svc_pre,
        run     => $svc_run,
        postrun => $svc_pos,
        title   => $svc_tit
    );
    is $svc->error, q{}, "add() service status";
    is $svc->name(),    $svc_nam, "  Name correct";
    is $svc->prerun(),  $svc_pre, "  PreRun correct";
    is $svc->run(),     $svc_run, "  Run correct";
    is $svc->postrun(), $svc_pos, "  PostRun correct";
    is $svc->title(),   $svc_tit, "  Title correct";
    is $svc->type(),    $svc_typ, "  Type correct";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Load it back as a new object
    $svc = Init::Service->new();    # make new object
    ok $svc, "Service object created for load";
    $svc->load($svc_nam);
    is $svc->error, q{}, "load() status";
    is $svc->name(),    $svc_nam, "  Name correct";
    is $svc->prerun(),  $svc_pre, "  PreRun correct";
    is $svc->run(),     $svc_run, "  Run correct";
    is $svc->postrun(), $svc_pos, "  PostRun correct";
    is $svc->title(),   $svc_tit, "  Title correct";
    is $svc->type(),    $svc_typ, "  Type correct";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Enable it for boot
    diag "";
    diag "--- Enable boot of the dummy service ---";
    $svc->enable();
    is $svc->error, q{}, "enable() status";
    ok !$svc->running(), "  Not running";
    ok $svc->enabled(),  "  Is enabled for boot";

    # Reload, check if enabled
    $svc = Init::Service->new();    # make new object
    ok $svc, "New object to check above";
    $svc->load($svc_nam);
    is $svc->error, q{}, "re-load() status";
    is $svc->name(),    $svc_nam, "  Name correct";
    is $svc->prerun(),  $svc_pre, "  PreRun correct";
    is $svc->run(),     $svc_run, "  Run correct";
    is $svc->postrun(), $svc_pos, "  PostRun correct";
    is $svc->title(),   $svc_tit, "  Title correct";
    is $svc->type(),    $svc_typ, "  Type correct";
    ok !$svc->running(), "  Not running";
    ok $svc->enabled(),  "  Is enabled for boot";

    # Disable from boot
    diag "";
    diag "--- Disable boot of the dummy service ---";
    $svc->disable();
    is $svc->error, q{}, "disable() status";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Reload, check if disabled
    $svc = Init::Service->new();    # make new object
    ok $svc, "New object to check above";
    $svc->load($svc_nam);
    is $svc->error, q{}, "re-load() status";
    is $svc->name(),    $svc_nam, "  Name correct";
    is $svc->prerun(),  $svc_pre, "  PreRun correct";
    is $svc->run(),     $svc_run, "  Run correct";
    is $svc->postrun(), $svc_pos, "  PostRun correct";
    is $svc->title(),   $svc_tit, "  Title correct";
    is $svc->type(),    $svc_typ, "  Type correct";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Start it
    diag "";
    diag "--- Start the dummy service ---";
    $svc->start();
    is $svc->error, q{}, "start() status";
    ok $svc->running(),  "  Is running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Reload, check if running
    $svc = Init::Service->new();    # make new object
    ok $svc, "New object to check above";
    $svc->load($svc_nam);
    is $svc->error, q{}, "re-load() status";
    is $svc->name(),    $svc_nam, "  Name correct";
    is $svc->prerun(),  $svc_pre, "  PreRun correct";
    is $svc->run(),     $svc_run, "  Run correct";
    is $svc->postrun(), $svc_pos, "  PostRun correct";
    is $svc->title(),   $svc_tit, "  Title correct";
    is $svc->type(),    $svc_typ, "  Type correct";
    ok $svc->running(),  "  Is running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Look for it on the system
    sleep 1;    # give it time to start, if system is busy
    my $out
        = qx(ps --no-header wax | /bin/grep -v grep | /bin/grep '$svc_run' 2>&1);
    isnt $out, q{}, " Service found on system";

    # Stop it
    diag "";
    diag "--- Stop the dummy service ---";
    $svc->stop();
    is $svc->error, q{}, "stop() status";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Reload, check if stopped
    $svc = Init::Service->new();    # make new object
    ok $svc, "New object to check above";
    $svc->load($svc_nam);
    is $svc->error, q{}, "re-load() status";
    is $svc->name(),    $svc_nam, "  Name correct";
    is $svc->prerun(),  $svc_pre, "  PreRun correct";
    is $svc->run(),     $svc_run, "  Run correct";
    is $svc->title(),   $svc_tit, "  Title correct";
    is $svc->postrun(), $svc_pos, "  PostRun correct";
    is $svc->type(),    $svc_typ, "  Type correct";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Remove it
    diag "";
    diag "--- Remove the dummy service ---";
    $svc = Init::Service->new();    # make new object
    ok $svc, "Service object created for remove";
    $svc->remove($svc_nam);
    is $svc->error, q{}, "remove() status";
    is $svc->name(),    q{}, "  Name empty";
    is $svc->prerun(),  q{}, "  PreRun empty";
    is $svc->run(),     q{}, "  Run empty";
    is $svc->postrun(), q{}, "  PostRun empty";
    is $svc->title(),   q{}, "  Title empty";
    is $svc->type(),    q{}, "  Type empty";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled";

    # Remove dummy daemon
    unlink $svc_exe;
}

exit 0;

