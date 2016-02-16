#!/usr/bin/perl -w
use strict;

# I'm first implementing this in Perl, because I'm fast at Perl.
# Then I'll convert it to a /bin/sh script, at which I'm slower doing.
# Thus, this Perl script is temporary and will go away.

my $ITYP_SYSV    = 'v';
my $ITYP_UPSTART = 'u';
my $ITYP_SYSTEMD = 'd';

# dispatch
usage("*** Missing command", 1) unless @ARGV >= 2;
my $svc = $ARGV[0];
my $cmd = lc $ARGV[1];
my $ityp
    = -r "/etc/init/$svc.conf"              ? $ITYP_UPSTART
    : -r "/etc/systemd/system/$svc.service" ? $ITYP_SYSTEMD
    : -r "/etc/init.d/$svc"                 ? $ITYP_SYSV
    :   usage("*** Service name '$svc' unknown", 2);

$cmd eq 'start'         ? do_start($svc)
    : $cmd eq 'stop'    ? do_stop($svc)
    : $cmd eq 'restart' ? do_restart($svc)
    : $cmd eq 'reload'  ? do_reload($svc)
    : $cmd eq 'status'  ? do_status($svc)
    : $cmd eq 'enable'  ? do_enable($svc)
    : $cmd eq 'disable' ? do_disable($svc)
    : $cmd eq 'install' ? do_install($svc)
    : $cmd eq 'remove'  ? do_remove($svc)
    :                     usage("*** Unknown command '$cmd'", 1);
exit 0;

#                           ------- o -------

sub usage {
    print q{Usage: service service_name command
  Commands:
    start   - Runs the service; if already running, an error is emitted
    stop    - Stops a running service; if not running, an error is emitted
    restart - Stops then starts a service
    reload  - Sends a SIGHUP to the service, if running
    status  - Displays the status of the service
    enable  - Mark a service to be started at boot; does not affect current state
    disable - Make service not start at boot; does not affect current state
    install - Make the service known to the system
    remove  - Makes the service unknown to the system; will do a stop and disable first
};
    print shift . "\n" if @_;
    exit(shift || 0);
}

sub must_be_root {
    die "*** Must be root\n" if $>;
}

sub do_start {
    must_be_root();
}

sub do_stop {
    must_be_root();
}

sub do_restart {
    must_be_root();
}

sub do_reload {
    must_be_root();
}

sub do_status {
}

sub do_enable {
    must_be_root();
}

sub do_disable {
    must_be_root();
}

sub do_install {
    must_be_root();
}

sub do_remove {
    must_be_root();
}

