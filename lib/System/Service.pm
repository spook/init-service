package System::Service;

use 5.10.0;    # for // operator and say() function
use strict;
use warnings;

our $VERSION = '2017.03.13';

use constant INIT_UNKNOWN => "unknown";
use constant INIT_SYSTEMV => "SysVinit";
use constant INIT_UPSTART => "upstart";
use constant INIT_SYSTEMD => "systemd";
use constant OK_TYPES     => qw/simple service forking notify oneshot task/;
use constant OK_ARGS      => qw/
    root
    initfile
    initsys
    name
    title
    type
    prerun
    run
    postrun

    err
    enabled
    started
    /;
my %ALIAS_LIST = (    # Don't do 'use constant' for this
    "description"   => "title",
    "lable"         => "title",
    "pre-start"     => "prerun",
    "execstartpre"  => "prerun",
    "command"       => "run",
    "exec"          => "run",
    "execstart"     => "run",
    "post-start"    => "postrun",
    "execstartpost" => "postrun",
);

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;    # Get the class name
    my $this  = {
        err      => q{},                  # Error status
        root     => q{},                  # File-system root (blank = /)
        initfile => q{},                  # Init script or file
        initsys  => q{},                  # Init system in use
        name     => q{},                  # Service name
        title    => q{},                  # Service description or title
        type     => q{},                  # Service type normal, fork, ...
        prerun   => q{},                  # pre-Command executable and arguments
        run      => q{},                  # Command executable and arguments
        postrun  => q{},                  # post-Command executable and arguments
        enabled  => 0,                    # Will start on boot
        started  => 0,                    # Running now
    };
    _process_args($this, @_);
    return $this->{err} if $this->{err};
    deduce_initsys($this) unless $this->{initsys};
    if (   ($this->{initsys} ne INIT_SYSTEMV)
        && ($this->{initsys} ne INIT_UPSTART)
        && ($this->{initsys} ne INIT_SYSTEMD))
    {
        $this->{err}     = "Unknown init system";
        $this->{initsys} = INIT_UNKNOWN;            # force to unknown, if passed-in was unknown
    }
    $class .= "::" . $this->{initsys};
    bless $this, $class;

    # Create or load on new
    if ($this->{name} && $this->{run}) {
        $this->add(@_);
    }
    elsif ($this->{name}) {
        $this->load($this->{name});
    }

    # Enabled or started on new?
    $this->enable() if !$this->error && $this->{name} && $this->{enabled};
    $this->start()  if !$this->error && $this->{name} && $this->{started};

    return $this;
}

sub deduce_initsys {
    my $this = shift;

    # Look for systemd
    my $ps_out = qx(ps -p 1 --no-headers -o comm 2>&1)
        || q{};    # 'comm' walks symlinks
    if (   -d "$this->{root}/lib/systemd"
        && -d "$this->{root}/etc/systemd"
        && $ps_out =~ m{\bsystemd\b})
    {
        return $this->{initsys} = INIT_SYSTEMD;
    }
    my $init_ver = qx($this->{root}/sbin/init --version 2>&1) || q{};
    if (-d "$this->{root}/etc/init"
        && $init_ver =~ m{\bupstart\b})
    {
        return $this->{initsys} = INIT_UPSTART;
    }
    if (-d "$this->{root}/etc/init.d") {
        return $this->{initsys} = INIT_SYSTEMV;
    }
    return $this->{initsys} = INIT_UNKNOWN;
}

sub _process_args {
    my $this = shift;
    while (@_) {
        my $k = lc shift;
        $k =~ s/^\s*(.+?)\s*$/$1/;    # trim
        my $v = shift // q{};         #/
        $this->{$k} = $v;
    }

    # Replace aliases
    while (my ($alias, $real) = each %ALIAS_LIST) {
        $this->{$real} = delete $this->{$alias} if $this->{$alias};
    }

    # Common checks
    if ($this->{name} && $this->{name} !~ m/^[\w\-\.\@\:]+$/i) {
        return $this->{err} = "Bad service name, must contain only a-zA-z0-9.-_\@:";
    }
    if ($this->{name} && (length($this->{name}) > 64)) {
        return $this->{err} = "Bad service name, maximum length is 64 characters";
    }
    if ($this->{type}) {
        $this->{type} = lc($this->{type});
        $this->{type} = "simple" if $this->{type} eq "service";
        $this->{type} = "oneshot" if $this->{type} eq "task";
        return $this->{err} = "Bad type, must be " . join(", ", OK_TYPES)
            unless grep $this->{type}, OK_TYPES;
    }

    # Only known keywords allowed
    foreach my $k (keys %$this) {
        return $this->{err} = "Unknown keyword: $k"
            unless grep $k, OK_ARGS;
    }

}

# Accessors
sub prerun   {return shift->{prerun};}
sub run      {return shift->{run};}
sub postrun  {return shift->{postrun};}
sub enabled  {return shift->{enabled};}
sub error    {return shift->{err};}
sub initfile {return shift->{initfile};}
sub initsys  {return shift->{initsys};}
sub name     {return shift->{name};}
sub running  {return shift->{running};}
sub title    {return shift->{title};}
sub type     {return shift->{type};}

#       ------- o -------

package System::Service::unknown;
our $VERSION = $System::Service::VERSION;
our @ISA     = qw/System::Service/;

# Return the error from the constructor
sub add     {return shift->{err};}
sub disable {return shift->{err};}
sub enable  {return shift->{err};}
sub load    {return shift->{err};}
sub remove  {return shift->{err};}
sub start   {return shift->{err};}
sub stop    {return shift->{err};}

#       ------- o -------

package System::Service::systemd;
our $VERSION = $System::Service::VERSION;
our @ISA     = qw/System::Service/;

sub add {
    my $this = shift;
    my %args = ();
    System::Service::_process_args(\%args, @_);
    return $this->{err} = $args{err} if $args{err};
    my $name  = $args{name};
    my $title = $args{title} // q{};       #/
    my $type  = $args{type} || "simple";
    my $pre   = $args{prerun};
    my $run   = $args{run};
    my $post  = $args{postrun};
    return $this->{err} = "Insufficient arguments; name and run required"
        if !$name || !$run;

    # Create unit file
    my $initfile = $this->{initfile} = "$this->{root}/lib/systemd/system/$name.service";
    return $this->{err} = "Service already exists: $name"
        if -e $initfile && !$args{force};

    open(UF, '>', $initfile)
        or return $this->{err} = "Cannot create init file $initfile: $!";
    say UF "[Unit]";
    say UF "Description=$title";

    say UF "";
    say UF "[Service]";
    say UF "ExecStartPre=$pre" if $pre;
    say UF "ExecStart=$run";
    say UF "ExecStartPost=$post" if $post;
    say UF "Type=$type";

    say UF "";
    say UF "[Install]";
    say UF "WantedBy=multi-user.target";    # TODO... how to map this?

    close UF;

    # Copy attributes into ourselves
    $this->{name}    = $name;
    $this->{title}   = $title;
    $this->{type}    = $type;
    $this->{prerun}  = $pre;
    $this->{run}     = $run;
    $this->{postrun} = $post;
    $this->{running} = 0;
    $this->{enabled} = 0;

    # Enabled or started on add?
    $this->{err} = q{};
    $this->enable() if $args{enabled};
    $this->start() if !$this->error && $args{started};

    return $this->{err};
}

sub disable {
    my $this = shift;
    return $this->{err} = "First load or add a service"
        unless $this->{name};
    my $out = qx(systemctl disable $this->{name}.service 2>&1);
    return $this->{err} = "Cannot disable $this->{name}: $!\n\t$out"
        if $?;
    $this->{enabled} = 0;
    return $this->{err} = q{};
}

sub enable {
    my $this = shift;
    return $this->{err} = "First load or add a service"
        unless $this->{name};
    my $out = qx(systemctl enable $this->{name}.service 2>&1);
    return $this->{err} = "Cannot enable $this->{name}: $!\n\t$out"
        if $?;
    $this->{enabled} = 1;
    return $this->{err} = q{};
}

sub load {
    my $this = shift;
    my $name = shift;

    my @lines = qx(systemctl show $name.service 2>&1);
    my %info = map {split(/=/, $_, 2)} @lines;
    return $this->{err} = "No such service $name"
        if !%info || $info{LoadState} !~ m/loaded/i;
    my $pre = $info{ExecStartPre} || q{};
    $pre = $1 if $pre =~ m{argv\[]=(.+?)\s*\;};
    my $run = $info{ExecStart} || q{};
    $run = $1 if $run =~ m{argv\[]=(.+?)\s*\;};
    my $post = $info{ExecStartPost} || q{};
    $post = $1 if $post =~ m{argv\[]=(.+?)\s*\;};
    $this->{name}    = $name;
    $this->{prerun}  = $pre;
    $this->{run}     = $run;
    $this->{postrun} = $post;
    $this->{title}   = $info{Description};
    $this->{type}    = $info{Type};
    $this->{running} = $info{SubState} =~ m/running/i ? 1 : 0;
    $this->{enabled} = $info{UnitFileState} =~ m/enabled/i ? 1 : 0;
    $this->{initfile} = "$this->{root}/lib/systemd/system/$name.service";

    foreach my $k (qw/prerun run postrun title type/) {
        chomp $this->{$k};
    }
}

sub remove {
    my $this = shift;
    my $name = shift;
    my %args;
    System::Service::_process_args(\%args, @_);

    # If we're removing it, we must first insure its stopped and disabled
    $this->stop($name);    #ignore errors except...? XXX
    $this->disable($name);

    # Now remove the unit file(s)
    my $initfile = "$this->{root}/lib/systemd/system/$name.service";
    return $this->{err} = "Service does not exist: $name"
        if !-e $initfile && !$args{force};
    my $n = unlink $initfile;
    return $this->{err} = "Cannot remove service $name: $!" unless $n;
    $this->{name}    = q{};
    $this->{prerun}  = q{};
    $this->{run}     = q{};
    $this->{postrun} = q{};
    $this->{title}   = q{};
    $this->{type}    = q{};
    $this->{initfile} = q{};
    $this->{running} = 0;
    $this->{enabled} = 0;
    return $this->{err} = q{};
}

sub start {
    my $this = shift;
    return $this->{err} = "First load or add a service"
        unless $this->{name};
    my $out = qx(systemctl start $this->{name}.service 2>&1);
    return $this->{err} = "Cannot start $this->{name}: $!\n\t$out"
        if $?;
    $this->{running} = 1;
    return $this->{err} = q{};
}

sub stop {
    my $this = shift;
    return $this->{err} = "First load or add a service"
        unless $this->{name};
    my $out = qx(systemctl stop $this->{name}.service 2>&1);
    return $this->{err} = "Cannot stop $this->{name}: $!\n\t$out"
        if $?;
    $this->{running} = 0;
    return $this->{err} = q{};
}

#       ------- o -------

package System::Service::upstart;
our $VERSION = $System::Service::VERSION;
our @ISA     = qw/System::Service/;

sub add {
    my $this = shift;
    my %args = ();
    System::Service::_process_args(\%args, @_);
    return $this->{err} = $args{err} if $args{err};
    my $name  = $args{name};
    my $title = $args{title} // q{};       #/
    my $type  = $args{type} || "simple";
    my $pre   = $args{prerun};
    my $run   = $args{run};
    my $post  = $args{postrun};
    return $this->{err} = "Insufficient arguments; name and run required"
        if !$name || !$run;

    # Create conf file
    my $initfile = $this->{initfile} = "$this->{root}/etc/init/$name.conf";
    return $this->{err} = "Service already exists: $name"
        if !$args{force} && -e $initfile;
    open(UF, '>', $initfile)
        or return $this->{err} = "Cannot create init file $initfile: $!";
    say UF "# upstart init script for the $name service";
    say UF "description  \"$title\"";
    say UF "pre-start exec $pre" if $pre;
    say UF "exec $run";
    say UF "post-start exec $post" if $post;
    say UF "expect fork"           if $type eq "BLAHBLAHTBD";    # TODO what to use here?
    say UF "expect daemon"         if $type eq "forking";
    say UF "expect stop"           if $type eq "notify";
    close UF;

    # Copy attributes into ourselves
    $this->{name}    = $name;
    $this->{title}   = $title;
    $this->{type}    = $type;
    $this->{prerun}  = $pre;
    $this->{run}     = $run;
    $this->{postrun} = $post;
    $this->{running} = 0;
    $this->{enabled} = 0;

    # Enabled or started on add?
    $this->{err} = q{};
    $this->enable() if $args{enabled};
    $this->start() if !$this->error && $args{started};

    return $this->{err};
}

sub disable {
    my $this = shift;
    $this->{enabled} = 0;
    return $this->_enadis();
}

sub enable {
    my $this = shift;
    $this->{enabled} = 1;
    return $this->_enadis();
}

# Helper function - Enable or disable based on $this->{enabled} setting
sub _enadis {
    my $this = shift;
    my $name = $this->{name};

    # Inhale the file line by line, removing any existing start on / stop on clauses
    my $contents = q{};
    my $initfile = $this->{initfile};
    open(UF, '<', $initfile)
        or return $this->{err} = "Cannot open unit file $initfile: $!";
    while (my $line = <UF>) {
        next if $line =~ m{^\s*start\b}i;
        next if $line =~ m{^\s*stop\b}i;
        $contents .= $line;
    }
    close UF;

    # If we want to be enabled, add those clauses
    if ($this->{enabled}) {
        $contents .= "\n";
        $contents .= "start on runlevel [2345]\n";     # TODO map this somehow
        $contents .= "stop  on runlevel [!2345]\n";    # TODO map this somehow
    }

    # Rewrite it to a temp, then rename into place (it's an atomic operation)
    open(NF, '>', "$initfile-new")
        or return $this->{err} = "Cannot create unit file $initfile-new: $!";
    print NF $contents;
    close NF;
    rename "$initfile-new", $initfile
        or return $this->{err} = "Cannot move new unit file $initfile-new into place: $!";

    return $this->{err} = q{};
}

sub load {
    my $this = shift;
    my $name = shift;

    # Clear everything
    $this->{name}    = $name;
    $this->{title}   = q{};
    $this->{type}    = 'simple';
    $this->{prerun}  = q{};
    $this->{run}     = q{};
    $this->{postrun} = q{};
    $this->{running} = 0;
    $this->{enabled} = 0;

    # Parse the init file
    my $initfile = $this->{initfile} = "$this->{root}/etc/init/$name.conf";
    open(UF, '<', $initfile)
        or return $this->{err} = "No such service $name: cannot open $initfile: $!";
    while (my $line = <UF>) {
        $this->{title}   = $1        if $line =~ m{^\s*description\s+"?(.+?)"?\s*$}i;
        $this->{type}    = 'forking' if $line =~ m{^\s*expect\s+daemon\b}i;
        $this->{type}    = 'notify'  if $line =~ m{^\s*expect\s+stop\b}i;
        $this->{prerun}  = $1        if $line =~ m{^\s*pre-start\s+exec\s+(.+)$}i;
        $this->{run}     = $1        if $line =~ m{^\s*exec\s+(.+)$}i;
        $this->{postrun} = $1        if $line =~ m{^\s*post-start\s+exec\s+(.+)$}i;
        $this->{enabled} = 1         if $line =~ m{^\s*start\s+on\b}i;
    }
    close UF;

    # then also run `service $name status` to read current state
    # ex output:
    #   ssh start/running, process 12345
    #   xxx: unrecognized service
    # The format of the output can be summarized as follows:
    # <job> [ (<instance>)]<goal>/<status>[, process <PID>]
    #        [<section> process <PID>]
    my $out = qx($this->{root}/sbin/initctl status $name 2>&1);
    $this->{running} = 1 if !$? && $out =~ m{\b/running\b}i;
}

sub remove {
    my $this = shift;
    my $name = shift;
    my %args;
    System::Service::_process_args(\%args, @_);

    # If we're removing it, we must first insure its stopped and disabled
    $this->stop($name);    #ignore errors except...? XXX
    $this->disable($name);

    # Now remove the conf file
    my $initfile = "$this->{root}/etc/init/$name.conf";    # TODO; use the stored name
    return $this->{err} = "Service does not exist: $name"
        if !-e $initfile && !$args{force};
    my $n = unlink $initfile;
    return $this->{err} = "Cannot remove service $name: $!" unless $n;
    $this->{name}    = q{};
    $this->{prerun}  = q{};
    $this->{run}     = q{};
    $this->{postrun} = q{};
    $this->{title}   = q{};
    $this->{type}    = q{};
    $this->{running} = 0;
    $this->{enabled} = 0;
    $this->{initfile} = q{};
    return $this->{err} = q{};
}

sub start {
    my $this = shift;
    return $this->{err} = "First load or add a service"
        unless $this->{name};
    my $out = qx(service $this->{name} start 2>&1);
    return $this->{err} = "Cannot start $this->{name}: $!\n\t$out"
        if $?;
    $this->{running} = 1;
    return $this->{err} = q{};
}

sub stop {
    my $this = shift;
    return $this->{err} = "First load or add a service"
        unless $this->{name};
    my $out = qx(service $this->{name} stop 2>&1);
    return $this->{err} = "Cannot start $this->{name}: $!\n\t$out"
        if $?;
    $this->{running} = 0;
    return $this->{err} = q{};
}

#       ------- o -------

package System::Service::SysV;
our $VERSION = $System::Service::VERSION;
our @ISA     = qw/System::Service/;

sub add {
    my $this = shift;
    my %args = ();
    System::Service::_process_args(\%args, @_);
    return $this->{err} = $args{err} if $args{err};
    my $name  = $args{name};
    my $title = $args{title} // q{};       #/
    my $type  = $args{type} || "simple";
    my $pre   = $args{prerun};
    my $run   = $args{run};
    my $post  = $args{postrun};
    return $this->{err} = "Insufficient arguments; name and run required"
        if !$name || !$run;
    my ($daemon, $opts) = $run =~ m/^\s*(\S+)\s+(.+)$/;

    # Form the script
    my $script = <<"__EOSCRIPT__";
#! /bin/sh

### BEGIN INIT INFO
# Provides:          $name
# Required-Start:    \$local_fs \$remote_fs \$syslog \$time
# Required-Stop:     \$local_fs \$remote_fs \$syslog \$time
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: $title
### END INIT INFO

# /etc/init.d/$name: start and stop $title
# This script is autogenerated by System::Service -- do not alter the following:
### BEGIN System::Service
# Type:    $type
# Prerun:  $pre
# Run:     $run
# Postrun: $post
### END System::Service

set -e
umask 022
. /lib/lsb/init-functions
export PATH=/sbin:/bin:/usr/sbin:/usr/bin

case "$1" in
  start)
	log_daemon_msg "Starting $title" "$name" || true
	if start-stop-daemon --start --quiet --oknodo --pidfile /var/run/$name.pid --exec $daemon -- $opts; then
	    log_end_msg 0 || true
	else
	    log_end_msg 1 || true
	fi
	;;
  stop)
	log_daemon_msg "Stopping $title" "$name" || true
	if start-stop-daemon --stop --quiet --oknodo --pidfile /var/run/$name.pid; then
	    log_end_msg 0 || true
	else
	    log_end_msg 1 || true
	fi
	;;

  reload|force-reload)
	log_daemon_msg "Reloading $title" "$name" || true
	if start-stop-daemon --stop --signal 1 --quiet --oknodo --pidfile /var/run/$name.pid --exec $daemon; then
	    log_end_msg 0 || true
	else
	    log_end_msg 1 || true
	fi
	;;

  restart)
	log_daemon_msg "Restarting $title" "$name" || true
	start-stop-daemon --stop --quiet --oknodo --retry 30 --pidfile /var/run/$name.pid
	check_for_no_start log_end_msg
	check_dev_null log_end_msg
	if start-stop-daemon --start --quiet --oknodo --pidfile /var/run/$name.pid --exec $daemon -- $opts; then
	    log_end_msg 0 || true
	else
	    log_end_msg 1 || true
	fi
	;;

  status)
	status_of_proc -p /var/run/$name.pid $daemon $name && exit 0 || exit $?
	;;

  *)
	log_action_msg "Usage: /etc/init.d/$name {start|stop|reload|force-reload|restart|status}" || true
	exit 1
esac

exit 0
__EOSCRIPT__

    # Create the init file
    my $initfile = $this->{initfile} = "$this->{root}/etc/init.d/$name";
    open(IF, '>', $initfile)
        or return $this->{err} = "Cannot create init file $initfile: $!";
    print IF $script;
    close IF;

    # Copy attributes into ourselves
    $this->{name}    = $name;
    $this->{title}   = $title;
    $this->{type}    = $type;
    $this->{prerun}  = $pre;
    $this->{run}     = $run;
    $this->{postrun} = $post;
    $this->{running} = 0;
    $this->{enabled} = 0;

    # Enabled or started on add?
    $this->{err} = q{};
    $this->enable() if $args{enabled};
    $this->start() if !$this->error && $args{started};

    return $this->{err};
}

sub disable {
}

sub enable {
}

sub load {
    my $this = shift;
    my $name = shift;

    # Clear everything
    $this->{name}    = $name;
    $this->{title}   = q{};
    $this->{type}    = 'simple';
    $this->{prerun}  = q{};
    $this->{run}     = q{};
    $this->{postrun} = q{};
    $this->{running} = 0;
    $this->{enabled} = 0;

    # Parse the init file
    my $initfile = $this->{initfile} = "$this->{root}/etc/init/$name.conf";
    open(UF, '<', $initfile)
        or return $this->{err} = "No such service $name: cannot open $initfile: $!";
    while (my $line = <UF>) {
        $this->{title}   = $1 if $line =~ m{^\s*#\s*short-description:\s+(.+?)\s*$}i;
        $this->{type}    = $1 if $line =~ m{^\s*#\s*type:\s*(.+?)\s*$}i;
        $this->{prerun}  = $1 if $line =~ m{^\s*#\s*prerun:\s*(.+?)\s*$}i;
        $this->{run}     = $1 if $line =~ m{^\s*#\s*run:\s*(.+?)\s*$}i;
        $this->{postrun} = $1 if $line =~ m{^\s*#\s*postrun:\s*(.+?)\s*$}i;
    }
    close UF;

    # Run the init's status to see if it's running
    my $out = qx($initfile status 2>&1);
    $this->{running} = 1 if !$? && $out =~ m{\b/is\s+running\b}i;

    # Use update-rc.d or chkconfig to check if it's enabled at boot
    my $cmdurc = "$this->{root}/usr/sbin/update-rc.d";
    my $cmdchk = "$this->{root}/sbin/chkconfig";
    if (-x $cmdurc) {

        # We don't use the command here - but ensure it's there
        # Instead we look for start links at runlevels 2 3 4 5
        my @startlinks = glob("$this->{root}/etc/rc[2345].d/S[0-9][0-9]$name");
        $this->{enabled} = @startlinks > 0 ? 1 : 0;
    }
    elsif (-x $cmdchk) {
        my $out = qx($cmdchk --list $name 2>&1) || q{};
        $this->{enabled} = $out =~ m{\s[2345]\:on\b}i;
    }
    else {
        return $this->{err} = "Cannot check boot state for $name";
    }
}

sub remove {

    # Remove script

    # Remove links: update-rc.d remove ...
}

sub start {
}

sub stop {
}

1;

__END__

=head1 NAME

System::Service - Manage system init services - SysV, upstart, systemd

=head1 VERSION

Version 2017.03.13

=head1 SYNOPSIS

Regardless of whether you use SysV, upstart, or systemd as your init system,
this module makes it easy to add/remove, enable/disable for boot, start/stop,
and check status on your system services.  It's essentially a wrapper around
each of the corresponding init system's equivalent functionality.

    use v5.10.0;
    use System::Service;
    my $svc = System::Service->new();

    # Show the underlying init system
    say $svc->initsys;

    # Load an existing service, to get info or check state
    my $err = $svc->load("foo-service");
    if ($err) { ... }
       # --or--
    $svc = System::Service->new(name => "foo-service");

    # Print service info
    say $svc->name;
    say $svc->type;
    say $svc->run;
    say $svc->enabled? "Enabled" : "Disabled";
    say $svc->running? "Running" : "Stopped";

    # Make new service known to the system (creates .service, .conf, or /etc/init.d file)
    $err = $svc->add(name => "foo-daemon",
                     run  => "/usr/bin/foo-daemon -D -p1234");
       # --or--
    $svc = System::Service->new( ...same args...)
    if ($svc->error) { ... }

    # Enable the service to start at boot
    $err = $svc->enable();

    # Start the service now (does not need to be enabled)
    $err = $svc->start();

    # On the flip side...
    $err = $svc->stop();
    $err = $svc->disable();
    $err = $svc->remove();
    
    ...

=head1 SUBROUTINES/METHODS

=head2 C<new>

Constructor.
With no arguments, it determines the type of init system in use, and creates an empty service 
object, which can later be add()'d or load()'d.  

    my $svc = new System::Service();
    if ($svc->error) { ... }

With at least both I<name> and I<run> passed, creates a new service on the system.
This is the same as calling an empty new() then calling add() with those arguments.

    my $svc = new System::Service(name => 'foo-daemon',
                                  run  => '/usr/bin/foo-daemon -D -p1234');
    if ($svc->error) { ... }

When called with I<name> but NOT I<run>, it will attempt to load() an existing service, if any.

    my $svc = new System::Service(name => 'foo-daemon');
    if ($svc->error) { ... }

Takes the same arguments as I<add()>.
Remember to check the object for an error after creating it.

=head2 C<deduce_initsys>

This is an internal function called by new().

It examines the system and determines what init system is in use.
To find out what init system is in use, call C<initsys()>.

=head2 C<prerun>

Returns the pre-run command(s) defined for the service.
For systemd, this is I<ExecStartPre>.
For upstart, this is I<pre-start exec>.
For SysVinit, these are pre-commands within the /etc/init.d script.
Multiple commands may exist; call this in list context to get them all.

=head2 C<run>

Returns the run command(s) defined for the service.
For systemd, this is I<ExecStart>.
For upstart, this is I<exec>.
For SysVinit, these are the main commands within the /etc/init.d script.
Multiple commands may exist; call this in list context to get them all.

Note - this does not 'run' the service now; it's just an accessor to 
return what's defined to be run.  To start the service now, use C<start()>.

=head2 C<postrun>

Returns the post-run command(s) defined for the service.
For systemd, this is I<ExecStartPost>.
For upstart, this is I<post-start exec>.
For SysVinit, these are the post-commands within the /etc/init.d script.
Multiple commands may exist; call this in list context to get them all.

=head2 C<enabled>

Returns a true/false value that indicates if the service is enabled to start at boot.

=head2 C<error>

Returns the current error status string for the service.
If no error (all is OK), returns an empty string which evaluates to false.
The normal way to use this is like:

    $svc->some_function(...);
    if ($svc->error) { ...handle error... }

=head2 C<initfile>

Returns the filename of the unit file, job file, or init script
used to start the service.

=head2 C<initsys>

Returns the name of the init system in use.
Possible values are 'unknown', 'SysVinit', 'upstart', or 'systemd'.

=head2 C<name>

Returns the service name.

=head2 C<running>

Returns true/false to indicate if the service is currently running.

=head2 C<title>

Returns a string that describes the service.
For systed, this is the I<Description> option.
For upstart, this is the I<description> stanza.
For SysVinit, this is the I<Short-Description> in the LSB header.

=head2 C<type>

Returns the service type.
Possibe values are simple, forking, notify, or oneshot.
For upstart, these are the mappings:

=over

=item *

'simple' is the job type 'service' without an 'expect' stanza;

=item *

'oneshot' is the jopb type 'task' without an 'expect' stanza;

=item *

'forking' is the job type 'task' with 'expect daemon' stanza;

=item *

'notify' is the job type 'task' with 'expect stop' stanza.

=back

For SysVinit, these service types are simulated.


=head2 C<add>

Adds a new service to the system.
Must be run as the root user.
This funciton will create necessary unit file, job file, or init script(s) on the system.
If the service already exists, an error is returned.
By default, the service is not started nor enambed for boot.

You must provide at least the I<name> and I<run> arguments to add a new service.

    $svc->add(name    => "foo-service",           # Required identifier for service
              title   => "Handles foo requests",  # Optional description
              prerun  => "/bin/foo-prep -a",      # Optional pre-start command(s)
              run     => "/bin/foo-daemon -D",    # Required command(s) to run the service
              postrun => "/bin/foo-fix -x",       # Optional post-start command(s)
              enabled => 1,                       # Optional, enable to start at boot
              started => 1,                       # Optional, start the service now
             );
    if ($svc->error) {
        die "*** Cannot add service: " . $svc->error;
    }

The service name must be a simple identifier, consisting only of alphanumeric characters,
dash "-", dot ".", underscore "_", colon ":", or the at-sign "@".  
The maximum length is 64 characters.

The prerun, run, and postrun commands must use absolute paths to the executable.
Multiple commands can be specified by passing an arrayref:

              run => ["/bin/foo-red -a 2",
                      "/bin/foo-daemon -D -p1234"]

To un-do an C<add()>, use C<remove()>.

=head2 C<disable>

Disables the service so that it will not start at boot.  This is the opposite of C<enable>.
This does not affect a running service instance; it only affects what happens at boot-time.

=head2 C<enable>

Enables the service so that it will start at boot.  This is the opposite of C<disable>.
This does not affect a stopped service instance; it only affects what happens at boot-time.

=head2 C<load>

Load the definition and status for the given service name.  Example:

    $svc->load("foo-service");
    if ($svc->error) { ... }
    say $svc->running ? "Foo is alive" : "Foo is not running";

=head2 C<remove>

Removes the service definition from the system; this makes the service unknown.
Any unit files, job files, or init scripts will be deleted.
If the service is running, it will be stopped first.
If the service is enabled for boot, it will be disabled.

To use this function, you must add() or load() it first.


=head1 AUTHOR

Uncle Spook, C<< <spook at MisfitMountain.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-system-service at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=System-Service>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc System::Service


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=System-Service>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/System-Service>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/System-Service>

=item * Search CPAN

L<http://search.cpan.org/dist/System-Service/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

This program is released under the following license: MIT

Copyright 2017 Uncle Spook.
See https://github.com/spook/service

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and 
associated documentation files (the "Software"), to deal in the Software without restriction, 
including without limitation the rights to use, copy, modify, merge, publish, distribute, 
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is 
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or 
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT 
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND 
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, 
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=cut

To Do:
* Rename the whole thing to something better, perhaps:  InitSys::Service ?
* sysVinit implementation
* shutdown commands: stop, prestop, but no poststop
* commands can be list ref's
    - and if non-oneshot for systemd, create/remove temp /bin/sh script
* allow to specify user & group for service
* Watchdog capability
* Mechanism to return warnings, then
    - is_warn(), is_error(), is_ok() ... or warning() funcs?
    - add if existing is warning
    - remove not there is warning
* Handle other initsys's like launchd, Service Management Facility, runit, Mudur, procd...


Other references:

* How to find out if you're running SysV, upstart, or systemd:
http://unix.stackexchange.com/questions/196166/how-to-find-out-if-a-system-uses-sysv-upstart-or-systemd-initsystem

* Upstart intro & Cookbook:
http://upstart.ubuntu.com/cookbook

* Details on what systemd does when there are also SysV init.d scripts in place:
http://unix.stackexchange.com/questions/233468/how-does-systemd-use-etc-init-d-scripts
The answer by JdeBP seems most correct.  He also provides good furthur reading.



