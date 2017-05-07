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
    diag "--- Create a dummy daemon ---";
    my @prr;
    my @por;
    my @prs;
    my @pos;
    my $svc_nam = "test-020";
    my $svc_prr = ["/bin/echo this is the prerun command", 
                   "/bin/true 1 2 3"];
    my $svc_dmn = "/tmp/$svc_nam.sh";
    my $svc_run = "$svc_dmn 'a' \"b c\"";   # Has single & double quotes
    my $svc_por = ["/bin/true 99", 
                   "/bin/echo Doing my post-run sequence", 
                   "/bin/echo Ta da, I am done"];
    my $svc_prs = ["/bin/echo prestop-one", 
                   "/bin/echo prestop-two"];
    my $svc_pos = ["/bin/echo 't-minus 9'", 
                   "/bin/echo 't-minus 8'"];
    my $svc_ttl = "Test ''service'' 'tis \"20\" for Init::Service"; # Has single & double quotes
    my $svc_typ = "simple";
    open D, ">", $svc_dmn
        or die "*** Cannot create daemon script $svc_dmn: $!";
    print D "#!/bin/sh\n";
    print D "echo \$\$ > /var/run/$svc_nam.pid\n";
    print D "sleep 1\n";
    print D "echo Got \$*\n";
    print D "sleep 28\n";
    print D "rm /var/run/$svc_nam.pid\n";
    print D "exit 0\n";
    close D;
    chmod 775, $svc_dmn
        or die "*** Cannot chmod() daemon script $svc_dmn: $!";
    ok 1, "Dummy daemon script created";

    # Add
    diag " ";
    diag "--- new() the dummy service ---";
    my $svc = Init::Service->new();
    ok $svc, "Service object created";
    is $svc->error, q{}, "  No error";
    $svc->add(
        name     => $svc_nam,
        type     => $svc_typ,
        prerun   => $svc_prr,
        runcmd   => $svc_run,
        postrun  => $svc_por,
        prestop  => $svc_prs,
        poststop => $svc_pos,
        title    => $svc_ttl,
    );
    @prr = $svc->prerun();
    @por = $svc->postrun();
    @prs = $svc->prestop();
    @pos = $svc->poststop();
    is $svc->error, q{}, "add() service status";
    is $svc->name(),    $svc_nam,   "  Name correct";
    is_deeply \@prr,    $svc_prr,   "  PreRun correct";
    is dq($svc->runcmd),dq($svc_run),"  RunCmd correct";
    is_deeply \@por,    $svc_por,   "  PostRun correct";
    is $svc->title(),   $svc_ttl,   "  Title correct";
    is $svc->type(),    $svc_typ,   "  Type correct";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Load it back as a new object
    $svc = Init::Service->new();    # make new object
    ok $svc, "Service object created for load";
    $svc->load($svc_nam);
    @prr = $svc->prerun();
    @por = $svc->postrun();
    @prs = $svc->prestop();
    @pos = $svc->poststop();
    is $svc->error, q{}, "load() status";
    is $svc->name(),    $svc_nam,   "  Name correct";
    is_deeply \@prr,    $svc_prr,   "  PreRun correct";
    is dq($svc->runcmd),dq($svc_run),"  RunCmd correct";
    is_deeply \@por,    $svc_por,   "  PostRun correct";
    is $svc->title(),   $svc_ttl,   "  Title correct";
    is $svc->type(),    $svc_typ,   "  Type correct";
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
    @prr = $svc->prerun();
    @por = $svc->postrun();
    @prs = $svc->prestop();
    @pos = $svc->poststop();
    is $svc->error, q{}, "re-load() status";
    is $svc->name(),    $svc_nam,   "  Name correct";
    is_deeply \@prr,    $svc_prr,   "  PreRun correct";
    is dq($svc->runcmd),dq($svc_run),"  RunCmd correct";
    is_deeply \@por,    $svc_por,   "  PostRun correct";
    is $svc->title(),   $svc_ttl,   "  Title correct";
    is $svc->type(),    $svc_typ,   "  Type correct";
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
    @prr = $svc->prerun();
    @por = $svc->postrun();
    @prs = $svc->prestop();
    @pos = $svc->poststop();
    is $svc->error, q{}, "re-load() status";
    is $svc->name(),    $svc_nam,   "  Name correct";
    is_deeply \@prr,    $svc_prr,   "  PreRun correct";
    is dq($svc->runcmd),dq($svc_run),"  RunCmd correct";
    is_deeply \@por,    $svc_por,   "  PostRun correct";
    is $svc->title(),   $svc_ttl,   "  Title correct";
    is $svc->type(),    $svc_typ,   "  Type correct";
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
    @prr = $svc->prerun();
    @por = $svc->postrun();
    @prs = $svc->prestop();
    @pos = $svc->poststop();
    is $svc->error, q{}, "re-load() status";
    is $svc->name(),    $svc_nam,   "  Name correct";
    is_deeply \@prr,    $svc_prr,   "  PreRun correct";
    is dq($svc->runcmd),dq($svc_run),"  RunCmd correct";
    is_deeply \@por,    $svc_por,   "  PostRun correct";
    is $svc->title(),   $svc_ttl,   "  Title correct";
    is $svc->type(),    $svc_typ,   "  Type correct";
    ok $svc->running(),  "  Is running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Look for it on the system
    sleep 1;    # give it time to start, if system is busy
    my $out
        = qx(ps --no-header wax | /bin/grep -v grep | /bin/grep '$svc_dmn' 2>&1);
    isnt $out, q{}, "  Service found on system";

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
    @prr = $svc->prerun();
    @por = $svc->postrun();
    @prs = $svc->prestop();
    @pos = $svc->poststop();
    is $svc->error, q{}, "re-load() status";
    is $svc->name(),    $svc_nam,   "  Name correct";
    is_deeply \@prr,    $svc_prr,   "  PreRun correct";
    is dq($svc->runcmd),dq($svc_run),"  RunCmd correct";
    is_deeply \@por,    $svc_por,   "  PostRun correct";
    is $svc->title(),   $svc_ttl,   "  Title correct";
    is $svc->type(),    $svc_typ,   "  Type correct";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled for boot";

    # Remove it
    diag "";
    diag "--- Remove the dummy service ---";
    $svc = Init::Service->new();    # make new object
    ok $svc, "Service object created for remove";
    $svc->remove($svc_nam);
    @prr = $svc->prerun();
    @por = $svc->postrun();
    @prs = $svc->prestop();
    @pos = $svc->poststop();
    is $svc->error, q{}, "remove() status";
    is $svc->name(),    q{}, "  Name empty";
    is scalar(@prr),    0,   "  PreRun empty";
    is $svc->runcmd(),  q{}, "  RunCmd empty";
    is scalar(@por),    0,   "  PostRun empty";
    is scalar(@prs),    0,   "  PreStop empty";
    is scalar(@pos),    0,   "  PostStop empty";
    is $svc->title(),   q{}, "  Title empty";
    is $svc->type(),    q{}, "  Type empty";
    ok !$svc->running(), "  Not running";
    ok !$svc->enabled(), "  Not enabled";

    # Remove dummy daemon
    unlink $svc_dmn;
}

exit 0;

