package Init::Service;

use 5.8.0;
use strict;
use warnings;

our $VERSION = '2017.10.13';

use constant ERR_OK       => q{};
use constant INIT_UNKNOWN => "unknown";
use constant INIT_SYSTEMV => "SysVinit";
use constant INIT_UPSTART => "upstart";
use constant INIT_SYSTEMD => "systemd";

my %ALIAS_LIST = (    # Don't do 'use constant' for this
    "description"   => "title",
    "lable"         => "title",
    "pre"           => "prerun",
    "pre-start"     => "prerun",
    "execstartpre"  => "prerun",
    "command"       => "runcmd",
    "exec"          => "runcmd",
    "execstart"     => "runcmd",
    "post"          => "postrun",
    "post-start"    => "postrun",
    "execstartpost" => "postrun",
    "started"       => "start",
    "enabled"       => "enable",
);

# Valid options for functions
use constant OPTS_NEW => {
    DEFAULT  => "name",
    name     => \&_ok_name,
    useinit  => \&_ok_initsys,
    root     => 0,
    title    => 0,
    type     => \&_ok_type,
    prerun   => \&_ok_cmdlist,   # runpre
    runcmd   => 0,               # runcmd
    postrun  => \&_ok_cmdlist,   # runaft
    prestop  => \&_ok_cmdlist,   # stoppre
    poststop => \&_ok_cmdlist,   # stopaft
    enable   => 0,
    start    => 0,
    depends  => \&_ok_name_list,
    force    => 0,
};
use constant OPTS_ADD => {
    DEFAULT  => "name",
    name     => \&_ok_name,
    root     => 0,
    title    => 0,
    type     => \&_ok_type,
    prerun   => \&_ok_cmdlist,
    runcmd   => 0,
    postrun  => \&_ok_cmdlist,
    prestop  => \&_ok_cmdlist,   # stoppre
    poststop => \&_ok_cmdlist,   # stopaft
    enable   => 0,
    start    => 0,
    depends  => \&_ok_name_list,
    force    => 0,
};
use constant OPTS_ENA => {
    DEFAULT => "name",
    name    => \&_ok_name,
    root    => 0,
};
use constant OPTS_DIS => {
    DEFAULT => "name",
    name    => \&_ok_name,
    root    => 0,
};
use constant OPTS_LOAD => {
    DEFAULT => "name",
    name    => \&_ok_name,
    root    => 0,
};
use constant OPTS_REM => {
    DEFAULT => "name",
    name    => \&_ok_name,
    root    => 0,
    force   => 0,
};
use constant OPTS_START => {
    DEFAULT => "name",
    name    => \&_ok_name,
    root    => 0,
};
use constant OPTS_STOP => {
    DEFAULT => "name",
    name    => \&_ok_name,
    root    => 0,
};

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
        prerun   => [],                   # pre-Commands; executable and arguments
        runcmd   => q{},                  # Command executable and arguments
        postrun  => [],                   # post-Commands; executable and arguments
        prestop  => [],                   # pre-stop commands
        poststop => [],                   # post-stop commands
        depends  => [],                   # depends-upon service names, scalar or list
        on_boot  => 0,                    # Will start on boot
        started  => 0,                    # Running now
    };
    bless $this, $class;                  # May be re-blessed later
    my %opts = _ckopts($this, OPTS_NEW(), @_);
    return $this if $this->{err};
    $this->{initsys} = $opts{useinit} || $this->_deduce_initsys();
    $this->{err} = "Unknown init system" if $this->{initsys} eq INIT_UNKNOWN;

    $class .= "::" . $this->{initsys};
    bless $this, $class;

    # Create or load on new
    $this->add(force => $opts{force})
                  if $opts{name} &&  $opts{runcmd};
    return $this  if $this->{err};
    $this->load() if $opts{name} && !$opts{runcmd};
    return $this  if $this->{err};

    # Enabled or started on new?
    $this->enable() if !$this->error && $opts{name} && $opts{enable};
    return $this    if $this->{err};
    $this->start()  if !$this->error && $opts{name} && $opts{start};
    return $this;
}

# Check options:
#       %opts = _ckopts($this, {validopts, ...}, @_);
#       %opts = $this->_ckopts({validopts, ...}, @_);
#   Processes user-supplied options to a function call.
#   Options are cleaned-up:  lowercased, trimmed, leading dash removed, and de-aliased.
#   Then they're validated against the hashref of allowed options for this function.
#   If a valid option, and the validopts hash has a function as its value, then
#       that function is called with a ref to the option value,
#       to (possibly) cleanup the value and validate it's ok.
#   If an option name is a key in $this, then $this is updated.
#   All cleaned-up options are returned as a hash; typically assign this to %opts.
#   If @_ contains only one element, it is presumed to be the value for the DEFAULT validopt.
#   Error status is set in $this->{err}.
sub _ckopts {
    my $this = shift;
    my $vops = shift || {};
    my (undef, undef, undef, $func) = caller(1);
    my %opts = ();
    if (!%$vops && @_) {
        $this->{err} = "$func: does not take options";
        return ();
    }
    unshift @_, ($vops->{"DEFAULT"} || q{})    # handle single-option value
        if %$vops && @_ == 1;
    while (@_) {
        my $k = lc shift;
        $k =~ s/^\s*-?(.+?)\s*$/$1/;           # trim, remove leading dash if given
        my $v = shift || q{};                  # Want to use // but Perl 5.8
        $k = $ALIAS_LIST{$k} || $k;            # De-alias
        if (!exists $vops->{$k}) {
            $this->{err} = "$func: bad option '$k'";
            return ();
        }
        if ((ref($vops->{$k}) eq "CODE") && (my $err = $vops->{$k}->(\$v))) {
            $this->{err} = "$func: bad value for '$k': $err";
            return ();
        }
        $opts{$k} = $v;
        $this->{$k} = $v if exists $this->{$k};
    }
    $this->{err} = ERR_OK;
    return %opts;
}

sub _deduce_initsys {
    my $this = shift;

    # Look for systemd - quick way first, more thorough second
    if (-e "$this->{root}/bin/systemctl") {
        return $this->{initsys} = INIT_SYSTEMD;
    }
    my $ps_out = qx(ps -p 1 --no-headers -o comm 2>&1) || q{};    # 'comm' walks symlinks
    if (  (-d "$this->{root}/lib/systemd" || -d "$this->{root}/usr/lib/systemd")
        && -d "$this->{root}/etc/systemd"
        && $ps_out =~ m{\bsystemd\b})
    {
        return $this->{initsys} = INIT_SYSTEMD;
    }

    # Look for *newer* upstart's (0.6+) - old ones will still use SysV style
    my $init_ver = qx($this->{root}/sbin/init --version 2>&1) || q{};
    if (-d "$this->{root}/etc/init"
        && $init_ver =~ m{\bupstart\b})
    {
        return $this->{initsys} = INIT_UPSTART;
    }

    # At this point, probably SysVinit
    if (-d "$this->{root}/etc/init.d") {
        return $this->{initsys} = INIT_SYSTEMV;
    }
    return $this->{initsys} = INIT_UNKNOWN;
}

# Value cleaners & checkers
sub _ok_cmdlist {
    my $vp = shift;
    $$vp = [$$vp] unless ref($$vp);
    return ERR_OK;
}

sub _ok_initsys {
    my $vp = shift;
    $$vp =~ s{^\s*(.+?)\s*}{$1};    # trim
    $$vp = INIT_UNKNOWN if lc($$vp) eq "unknown";
    $$vp = INIT_SYSTEMV if lc($$vp) eq "sysv";
    $$vp = INIT_SYSTEMV if lc($$vp) eq "sysvinit";
    $$vp = INIT_UPSTART if lc($$vp) eq "upstart";
    $$vp = INIT_SYSTEMD if lc($$vp) eq "systemd";
    return ERR_OK;
}

sub _ok_name {
    my $vp = shift;
    $$vp =~ s{^\s*(.+?)\s*}{$1};    # trim
    return "empty"                  if $$vp eq q{};
    return "too long, max 64 chars" if length($$vp) > 64;
    return "only a-zA-z0-9.-_\@:"   if $$vp !~ m/^[\w\-\.\@\:]+$/i;
    return ERR_OK;
}

sub _ok_name_list {
    my $vp = shift;
    my @list = ref $$vp? @$$vp : ($$vp);
    foreach my $name (@list) {
        my $err = _ok_name(\$name);
        return $err if $err;
        }
    $$vp = \@list;
    return ERR_OK;
}

sub _ok_type {
    my $vp = shift;
    $$vp =~ s{^\s*(.+?)\s*}{$1};    # trim
    $$vp = lc $$vp;
    $$vp = "simple" if $$vp eq "service";
    $$vp = "oneshot" if $$vp eq "task";
    $$vp = "forking" if $$vp eq "daemon";
    return ERR_OK if $$vp eq "simple";
    return ERR_OK if $$vp eq "oneshot";
    return ERR_OK if $$vp eq "notify";
    return ERR_OK if $$vp eq "forking";
    return "must be simple, oneshot, notify, or forking";
}

# Accessors
sub depends  {return @{shift->{depends}};}
sub enabled  {return shift->{on_boot};}
sub error    {return shift->{err};}
sub initfile {return shift->{initfile};}
sub initsys  {return shift->{initsys};}
sub name     {return shift->{name};}
sub postrun  {return @{shift->{postrun}};}
sub poststop {return @{shift->{poststop}};}
sub prerun   {return @{shift->{prerun}};}
sub prestop  {return @{shift->{prestop}};}
sub runcmd   {return shift->{runcmd};}
sub running  {return shift->{running};}
sub title    {return shift->{title};}
sub type     {return shift->{type};}

#       ------- o -------

package Init::Service::unknown;
our $VERSION = $Init::Service::VERSION;
our @ISA     = qw/Init::Service/;

# Unknown initsys - return the error set in the constructor
sub add     {return shift->{err};}
sub disable {return shift->{err};}
sub enable  {return shift->{err};}
sub load    {return shift->{err};}
sub remove  {return shift->{err};}
sub start   {return shift->{err};}
sub stop    {return shift->{err};}

#       ------- o -------

package Init::Service::systemd;
our $VERSION = $Init::Service::VERSION;
our @ISA     = qw/Init::Service/;
use constant ERR_OK => Init::Service::ERR_OK;

sub add {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_ADD(), @_);
    return $this->{err} if $this->{err};
    my $name     = $this->{name};
    my $title    = $this->{title};
    my $type     = $this->{type} || "simple";
    my $prerun   = $this->{prerun};
    my $runcmd   = $this->{runcmd};
    my $postrun  = $this->{postrun};
    my $prestop  = $this->{prestop};
    my $poststop = $this->{prestop};
    my $depends  = $this->{depends};
    return $this->{err} = "Missing options; name and runcmd required"
        if !$name || !$runcmd;

    # Create unit file
    my $base = -d "$this->{root}/lib/systemd" ? "$this->{root}/lib/systemd" 
                                              : "$this->{root}/usr/lib/systemd";
    my $initfile = $this->{initfile} = "$base/system/$name.service";
    return $this->{err} = "Service exists: $name"
        if -e $initfile && !$opts{force};
    open(UF, '>', $initfile)
        or return $this->{err} = "Cannot create init file $initfile: $!";
    print UF "[Unit]\n";
    print UF "Description=$title\n";
    foreach my $dep (@$depends) {
        print UF "Requisite=$dep.service\n";
    }
    print UF "After=network.target syslog.target\n";
    foreach my $dep (@$depends) {
        print UF "After=$dep.service\n";
    }

    print UF "\n";
    print UF "[Service]\n";
    foreach my $cmd (@$prerun) {
        print UF "ExecStartPre=$cmd\n";
    }
    print UF "ExecStart=$runcmd\n";
    foreach my $cmd (@$postrun) {
        print UF "ExecStartPost=$cmd\n";
    }
    foreach my $cmd (@$prestop) {
        print UF "ExecStop=$cmd\n";
    }
    foreach my $cmd (@$poststop) {
        print UF "ExecStopPost=$cmd\n";
    }
    print UF "Type=$type\n";

    print UF "\n";
    print UF "[Install]\n";
    print UF "WantedBy=multi-user.target\n";    # TODO... how to map this?

    close UF;
    chmod 0644, $initfile
        or return $this->{err} = "Cannot chmod 644 file $initfile: $!";

    # Daemon reload
    my $out = qx(systemctl daemon-reload 2>&1);
    $! ||= 0;
    return $this->{err} = "Error on daemon-reload: $!\n\t$out"
        if $?;

    # Enabled or started on add?
    $this->{err}     = ERR_OK;
    $this->{type}    = $type;
    $this->{running} = 0;
    $this->{on_boot} = 0;
    $this->enable() if !$this->error && $opts{name} && $opts{enable};
    $this->start()  if !$this->error && $opts{name} && $opts{start};

    return $this->{err};
}

sub disable {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_DIS(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};

    my $out = qx(systemctl disable $this->{name}.service 2>&1);
    $! ||= 0;
    return $this->{err} = "Cannot disable $this->{name}: $!\n\t$out"
        if $?;

    $this->{on_boot} = 0;
    return $this->{err} = ERR_OK;
}

sub enable {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_ENA(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};
    my $out = qx(systemctl enable $this->{name}.service 2>&1);
    $! ||= 0;
    return $this->{err} = "Cannot enable $this->{name}: $!\n\t$out"
        if $?;
    $this->{on_boot} = 1;
    return $this->{err} = ERR_OK;
}

sub load {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_LOAD(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};
    my $name = $this->{name};

    # Clear everything first
    $this->{name}     = $name;
    $this->{title}    = q{};
    $this->{type}     = 'simple';
    $this->{prerun}   = [];
    $this->{runcmd}   = q{};
    $this->{postrun}  = [];
    $this->{prestop}  = [];
    $this->{poststop} = [];
    $this->{depends}  = [];
    $this->{running}  = 0;
    $this->{on_boot}  = 0;
    my $base = -d "$this->{root}/lib/systemd" ? "$this->{root}/lib/systemd" 
                                              : "$this->{root}/usr/lib/systemd";
    $this->{initfile} = "$base/system/$name.service";

    my $loadstate = "unknown";
    my @lines     = qx(systemctl show $name.service 2>&1);
    foreach my $line (@lines) {
        chomp $line;
        my ($k, $v) = split(/=/, $line, 2);
        if ($k eq 'LoadState') {
            $loadstate = $v;
            next;
        }
        if ($k eq 'ExecStartPre') {
            $v = $1 if $v =~ m{argv\[]=(.+?)\s*\;};
            next unless $v; # Cannot have blank commands here
            push @{$this->{prerun}}, $v;
            next;
        }
        if ($k eq 'ExecStart') {

            # Our 'runcmd' can be only a single command; if we get several,
            # push the prior back to the prerun
            push @{$this->{prerun}}, $this->{runcmd} if $this->{runcmd};

            $v = $1 if $v =~ m{argv\[]=(.+?)\s*\;};
            $this->{runcmd} = $v;
            next;
        }
        if ($k eq 'ExecStartPost') {
            $v = $1 if $v =~ m{argv\[]=(.+?)\s*\;};
            next unless $v; # Cannot have blank commands here
            push @{$this->{postrun}}, $v;
            next;
        }
        if ($k eq 'ExecStop') {
            $v = $1 if $v =~ m{argv\[]=(.+?)\s*\;};
            next unless $v; # Cannot have blank commands here
            push @{$this->{prestop}}, $v;
            next;
        }
        if ($k eq 'ExecStopPost') {
            $v = $1 if $v =~ m{argv\[]=(.+?)\s*\;};
            next unless $v; # Cannot have blank commands here
            push @{$this->{poststop}}, $v;
            next;
        }
        if ($k eq 'Requisite') {
            push @{$this->{depends}}, map {m{^(\S+)\.service$}} split(/\s+/, $v);
            next;
        }

        $this->{type}    = $v if  $k eq 'Type';
        $this->{title}   = $v if  $k eq 'Description';
        $this->{running} = 1  if ($k eq 'SubState')      && ($v =~ m/running/i);
        $this->{on_boot} = 1  if ($k eq 'UnitFileState') && ($v =~ m/enabled/i);
    }
    return $this->{err} = "No such service $name (LoadState=$loadstate)"
        if $loadstate !~ m/loaded/i;
    return $this->{err} = ERR_OK;
}

sub remove {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_REM(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};
    my $name = $this->{name};

    # If we're removing it, we must first insure its stopped and disabled
    $this->stop();    #ignore errors except...? XXX
    $this->disable();

    # Now remove the unit file(s)
    my $base = -d "$this->{root}/lib/systemd" ? "$this->{root}/lib/systemd" 
                                              : "$this->{root}/usr/lib/systemd";
    my $initfile = "$base/system/$name.service";
    return $this->{err} = "No such service $name"
        if !-e $initfile && !$opts{force};
    my $n = unlink $initfile;
    $! ||= 0;
    return $this->{err} = "Cannot remove service $name: $!" unless $n;

    # Clear all
    $this->{name}     = q{};
    $this->{prerun}   = [];
    $this->{runcmd}   = q{};
    $this->{postrun}  = [];
    $this->{prestop}  = [];
    $this->{poststop} = [];
    $this->{depends}  = [];
    $this->{title}    = q{};
    $this->{type}     = q{};
    $this->{initfile} = q{};
    $this->{running}  = 0;
    $this->{on_boot}  = 0;
    return $this->{err} = ERR_OK;
}

sub start {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_START(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};
    my $name = $this->{name};

    my $out = qx(systemctl start $name.service 2>&1);
    $! ||= 0;
    return $this->{err} = "Cannot start $name: $!\n\t$out"
        if $?;
    $this->{running} = 1;
    return $this->{err} = ERR_OK;
}

sub stop {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_STOP(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};
    my $name = $this->{name};

    my $out = qx(systemctl stop $name.service 2>&1);
    $! ||= 0;
    return $this->{err} = "Cannot stop $name: $!\n\t$out"
        if $?;
    $this->{running} = 0;
    return $this->{err} = ERR_OK;
}

#       ------- o -------

package Init::Service::upstart;
our $VERSION = $Init::Service::VERSION;
our @ISA     = qw/Init::Service/;
use constant ERR_OK => Init::Service::ERR_OK;

sub add {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_ADD(), @_);
    return $this->{err} if $this->{err};
    my $name     = $this->{name};
    my $title    = $this->{title};
    my $type     = $this->{type} || "simple";
    my $prerun   = $this->{prerun};
    my $runcmd   = $this->{runcmd};
    my $postrun  = $this->{postrun};
    my $prestop  = $this->{prestop};
    my $poststop = $this->{prestop};
    my $depends  = $this->{depends};
    return $this->{err} = "Missing options; name and runcmd required"
        if !$name || !$runcmd;

    # Depends handling - do as pre-start script check
    my $predep = q{};
    foreach my $name (@$depends) {
        $predep .= "    # Depends\n" unless $predep;
        $predep .= "    if ! initctl status $name 2>/dev/null | grep -q running; then "
                 . "echo 'Failed dependency on service' $name; exit 1; fi\n";
    }
    $predep .= "    # End Depends\n" if $predep;

    # Create conf file
    my $initfile = $this->{initfile} = "$this->{root}/etc/init/$name.conf";
    return $this->{err} = "Service exists: $name"
        if -e $initfile && !$opts{force};
    open(UF, '>', $initfile)
        or return $this->{err} = "Cannot create init file $initfile: $!";
    print UF "# upstart init script for the $name service\n";
    print UF "description  \"$title\"\n";
    print UF "pre-start script\n" if @$prerun || $predep;
    print UF $predep if $predep;
    foreach my $cmd (@$prerun) {
        print UF "    $cmd\n";
    }
    print UF "end script\n" if @$prerun || $predep;
    print UF "exec $runcmd\n";
    print UF "post-start script\n" if @$postrun;
    foreach my $cmd (@$postrun) {
        print UF "    $cmd\n";
    }
    print UF "end script\n"    if @$postrun;
    print UF "expect fork\n"   if $type eq "BLAHBLAHTBD";    # TODO what to use here?
    print UF "expect daemon\n" if $type eq "forking";
    print UF "expect stop\n"   if $type eq "notify";
    print UF "pre-stop script\n" if @$prestop;
    foreach my $cmd (@$prestop) {
        print UF "    $cmd\n";
    }
    print UF "end script\n" if @$prestop;
    print UF "post-stop script\n" if @$poststop;
    foreach my $cmd (@$poststop) {
        print UF "    $cmd\n";
    }
    print UF "end script\n" if @$poststop;

    # Add a stop on clause
    my $depsdn = q{};
    foreach my $name (@{$this->{depends}}) {
        $depsdn .= " or stopping $name";
    }
    print UF "stop  on runlevel [!2345]$depsdn\n";      # TODO map runlevels somehow

    close UF;
    chmod 0644, $initfile
        or return $this->{err} = "Cannot chmod 644 file $initfile: $!";

    # Enabled or started on add?
    $this->{err}     = ERR_OK;
    $this->{type}    = $type;
    $this->{running} = 0;
    $this->{on_boot} = 0;
    $this->enable() if !$this->error && $opts{name} && $opts{enable};
    $this->start()  if !$this->error && $opts{name} && $opts{start};

    return $this->{err};
}

sub disable {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_DIS(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};

    return $this->_enadis(0);
}

sub enable {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_ENA(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};

    return $this->_enadis(1);
}

# Helper function - Enable or disable
sub _enadis {
    my $this   = shift;
    my $enable = shift;
    my $name   = $this->{name};

    # Inhale the file line by line, removing any existing start on clauses
    my $contents = q{};
    my $initfile = $this->{initfile} || "$this->{root}/etc/init/$name.conf";
    open(UF, '<', $initfile)
        or return $this->{err} = "Cannot open unit file $initfile: $!";
    while (my $line = <UF>) {
        next if $line =~ m{^\s*start\b}i;
        $contents .= $line;
    }
    close UF;

    # Prep some stuff for depends
    my $depsup = q{};
    my $depsdn = q{};
    foreach my $name (@{$this->{depends}}) {
        $depsup .= " and started $name";
        $depsdn .= " or stopping $name";
    }

    # If we want to be enabled, add a start on clause
    if ($enable) {
        my $depsup = q{};
        foreach my $name (@{$this->{depends}}) {
            $depsup .= " and started $name";
        }
        $contents .= "\n";
        $contents .= "start on runlevel [2345]$depsup\n";   # TODO map runlevels somehow
    }

    # Rewrite it to a temp, then rename into place (it's an atomic operation)
    open(NF, '>', "$initfile-new")
        or return $this->{err} = "Cannot create unit file $initfile-new: $!";
    print NF $contents;
    close NF;
    rename "$initfile-new", $initfile
        or return $this->{err} = "Cannot move new unit file $initfile-new into place: $!";

    $this->{on_boot} = $enable;
    return $this->{err} = ERR_OK;
}

sub load {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_LOAD(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};
    my $name = $this->{name};

    # Clear everything first
    $this->{name}     = $name;
    $this->{title}    = q{};
    $this->{type}     = 'simple';
    $this->{prerun}   = [];
    $this->{runcmd}   = q{};
    $this->{postrun}  = [];
    $this->{prestop}  = [];
    $this->{poststop} = [];
    $this->{depends}  = [];
    $this->{running}  = 0;
    $this->{on_boot}  = 0;

    # Parse the init file
    my $initfile = $this->{initfile} = "$this->{root}/etc/init/$name.conf";
    open(UF, '<', $initfile)
        or return $this->{err} = "No such service $name: cannot open $initfile: $!";
    my $inprerun   = 0;
    my $inpostrun  = 0;
    my $inprestop  = 0;
    my $inpoststop = 0;
    while (my $line = <UF>) {
        if ($line =~ m{^\s*pre-start\s+exec\s+(.+)$}i) {
            push @{$this->{prerun}}, $1;
            next;
        }
        if ($line =~ m{^\s*pre-start\s+script\s*$}i) {
            $inprerun = 1;
            next;
        }
        if ($inprerun) {
            if ($line =~ m{^\s*end\s+script\s*$}i) {
                $inprerun = 0;
            }
            else {
                chomp $line;
                $line =~ s{^\s{4}}{};
                push @{$this->{prerun}}, $line;
            }
            next;
        }

        if ($line =~ m{^\s*post-start\s+exec\s+(.+)$}i) {
            push @{$this->{postrun}}, $1;
            next;
        }
        if ($line =~ m{^\s*post-start\s+script\s*$}i) {
            $inpostrun = 1;
            next;
        }
        if ($inpostrun) {
            if ($line =~ m{^\s*end\s+script\s*$}i) {
                $inpostrun = 0;
            }
            else {
                chomp $line;
                $line =~ s{^\s{4}}{};
                push @{$this->{postrun}}, $line;
            }
            next;
        }

        if ($line =~ m{^\s*pre-stop\s+exec\s+(.+)$}i) {
            push @{$this->{prestop}}, $1;
            next;
        }
        if ($line =~ m{^\s*pre-stop\s+script\s*$}i) {
            $inprestop = 1;
            next;
        }
        if ($inprestop) {
            if ($line =~ m{^\s*end\s+script\s*$}i) {
                $inprestop = 0;
            }
            else {
                chomp $line;
                $line =~ s{^\s{4}}{};
                push @{$this->{prestop}}, $line;
            }
            next;
        }

        if ($line =~ m{^\s*post-stop\s+exec\s+(.+)$}i) {
            push @{$this->{poststop}}, $1;
            next;
        }
        if ($line =~ m{^\s*post-stop\s+script\s*$}i) {
            $inpoststop = 1;
            next;
        }
        if ($inpoststop) {
            if ($line =~ m{^\s*end\s+script\s*$}i) {
                $inpoststop = 0;
            }
            else {
                chomp $line;
                $line =~ s{^\s{4}}{};
                push @{$this->{poststop}}, $line;
            }
            next;
        }

        $this->{title}   = $1        if $line =~ m{^\s*description\s+"?(.+?)"?\s*$}i;
        $this->{type}    = 'forking' if $line =~ m{^\s*expect\s+daemon\b}i;
        $this->{type}    = 'notify'  if $line =~ m{^\s*expect\s+stop\b}i;
        $this->{runcmd}  = $1        if $line =~ m{^\s*exec\s+(.+)$}i;
        $this->{postrun} = $1        if $line =~ m{^\s*post-start\s+exec\s+(.+)$}i;
        $this->{on_boot} = 1         if $line =~ m{^\s*start\s+on\b}i;
    }
    close UF;

    # Dependent services are buried in the pre-run script; pull those out
    if (@{$this->{prerun}} && ($this->{prerun}->[0] eq "# Depends")) {
        while (1) {
            last unless @{$this->{prerun}};
            my $line = shift @{$this->{prerun}};
            last unless $line;
            last if $line eq "# End Depends";
            next unless $line =~ m{if ! initctl status (\S+)};
            push @{$this->{depends}}, $1;
        }
    }

    # then also run `initctl status $name` to read current state
    # ex output:
    #   ssh start/running, process 12345
    #       -or-
    #   ssh: unrecognized service
    # The format of the output can be summarized as follows:
    # <job> [ (<instance>)]<goal>/<status>[, process <PID>]
    #        [<section> process <PID>]
    my $out = qx($this->{root}/sbin/initctl status $name 2>&1);
    $this->{running} = 1 if !$? && $out =~ m{\b/running\b}i;

    return $this->{err} = ERR_OK;
}

sub remove {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_REM(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};
    my $name = $this->{name};

    # If we're removing it, we must first insure its stopped and disabled
    $this->stop();    #ignore errors except...? XXX
    $this->disable();

    # Now remove the conf file
    my $initfile = "$this->{root}/etc/init/$name.conf";    # TODO; use the stored name
    return $this->{err} = "No such service $name"
        if !-e $initfile && !$opts{force};
    my $n = unlink $initfile;
    $! ||= 0;
    return $this->{err} = "Cannot remove service $name: $!" unless $n;

    # Clear all
    $this->{name}     = q{};
    $this->{prerun}   = [];
    $this->{runcmd}   = q{};
    $this->{postrun}  = [];
    $this->{prestop}  = [];
    $this->{poststop} = [];
    $this->{depends}  = [];
    $this->{title}    = q{};
    $this->{type}     = q{};
    $this->{initfile} = q{};
    $this->{running}  = 0;
    $this->{on_boot}  = 0;
    return $this->{err} = ERR_OK;
}

sub start {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_START(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};
    my $name = $this->{name};

    my $out = qx(start $this->{name} 2>&1);
    $! ||= 0;
    $? = 0 if $out =~ m{already running};
    return $this->{err} = "Cannot start $name: ($!) $out"
        if $?;
    $this->{running} = 1;
    return $this->{err} = ERR_OK;
}

sub stop {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_STOP(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};
    my $name = $this->{name};

    my $out = qx(stop $name 2>&1);
    $! ||= 0;
    $? = 0 if $out =~ m{Unknown instance};
    return $this->{err} = "Cannot stop $name: ($!) $out"
        if $?;
    $this->{running} = 0;
    return $this->{err} = ERR_OK;
}

#       ------- o -------

package Init::Service::SysVinit;
our $VERSION = $Init::Service::VERSION;
our @ISA     = qw/Init::Service/;
use constant ERR_OK => Init::Service::ERR_OK;

sub add {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_ADD(), @_);
    return $this->{err} if $this->{err};
    my $root     = $this->{root}  || q{};
    my $name     = $this->{name};
    my $title    = $this->{title} || $name;     # Cannot be blank for chkconfig
    my $type     = $this->{type}  || "simple";
    my $prerun   = $this->{prerun};
    my $runcmd   = $this->{runcmd};
    my $postrun  = $this->{postrun};
    my $prestop  = $this->{prestop};
    my $poststop = $this->{poststop};
    my $depends  = $this->{depends};
    return $this->{err} = "Missing options; name and runcmd required"
        if !$name || !$runcmd;

    my ($daemon, $dopts) = split(/\s+/, $runcmd, 2);
    $dopts ||= q{};
    $dopts =~ s{('+)}{'"$1"'}g; # protect singe-quote
    my $bgflag_ub = ($type eq "simple") || ($type eq "notify") ? "--background" : q{};
    my $bgflag_rh = ($type eq "simple") || ($type eq "notify") ? "&"            : q{};

    my $deplist  = join(q{ }, @$depends);
    my $depchunk = q{};
    foreach my $depname (@$depends) {
        $depchunk .= "if ! ckdep \"$depname\"; then "
                  . "echo 'Error: failed dependency on service' $name; exit 1; fi\n";
    }
    my $prestartchunk = q{};
    if (@$prerun) {
        $prestartchunk
            = "# BEGIN PRE-START"
            . "\n    log_daemon_msg \"Pre-Start  $title\" \"$name\" || true"
            . "\n    "
            . join("\n    ", @$prerun)
            . "\n    log_end_msg 0 || true"
            . "\n    # END PRE-START";
    }
    my $poststartchunk = q{};
    if (@$postrun) {
        $poststartchunk
            = "# BEGIN POST-START"
            . "\n    log_daemon_msg \"Post-Start $title\" \"$name\" || true"
            . "\n    "
            . join("\n    ", @$postrun)
            . "\n    log_end_msg 0 || true"
            . "\n    # END POST-START";
    }
    my $prestopchunk = q{};
    if (@$prestop) {
        $prestopchunk
            = "# BEGIN PRE-STOP"
            . "\n    log_daemon_msg \"Pre-Stop  $title\" \"$name\" || true"
            . "\n    "
            . join("\n    ", @$prestop)
            . "\n    log_end_msg 0 || true"
            . "\n    # END PRE-STOP";
    }
    my $poststopchunk = q{};
    if (@$poststop) {
        $poststopchunk
            = "# BEGIN POST-STOP"
            . "\n    log_daemon_msg \"Post-Stop $title\" \"$name\" || true"
            . "\n    "
            . join("\n    ", @$poststop)
            . "\n    log_end_msg 0 || true"
            . "\n    # END POST-STOP";
    }

    # Form the script
    my $script = <<"__EOSCRIPT__";
#!/bin/sh
# /etc/init.d/$name: start and stop $title
# This script is autogenerated by Init::Service
# chkconfig:         2345 72 28
# description:       $title
# processname:       $name
# pidfile:           $root/var/run/$name.pid
### BEGIN INIT INFO
# Provides:          $name
# Required-Start:    \$network \$local_fs \$remote_fs \$syslog \$time
# Required-Stop:     \$network \$local_fs \$remote_fs \$syslog \$time
# Should-Start:      \$syslog \$named
# Should-Stop:       \$syslog \$named
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: $title
### END INIT INFO
# Depends:           $deplist

set +e
umask 022

TYPE=$type
NAME=$name
DOPTS='$dopts'
DAEMON=$daemon
PID_FILE=$root/var/run/$name.pid
LOG_FILE=$root/var/log/$name.log

# There's many variations of init.d script functions, figure out which we'll use
if [ -f /etc/init.d/functions ] ; then
    . /etc/init.d/functions
    START_CMD="daemon --pidfile \$PID_FILE --check nohup \$DAEMON \$DOPTS </dev/null >\$LOG_FILE 2>&1 $bgflag_rh"
elif [ -f /etc/rc.d/init.d/functions ] ; then
    . /etc/rc.d/init.d/functions
    START_CMD="daemon --pidfile \$PID_FILE --check nohup \$DAEMON \$DOPTS </dev/null >\$LOG_FILE 2>&1 $bgflag_rh"
elif [ -f /lib/lsb/init-functions ] ; then
    . /lib/lsb/init-functions
    START_CMD="start-stop-daemon --start --quiet --oknodo --pidfile \$PID_FILE --make-pidfile $bgflag_ub --exec \$DAEMON -- \$DOPTS"
else
    echo "*** init functions not available" 1>&2
    exit 5
fi
if [ -f \$PID_FILE ]; then
    STOP_CMD="killproc -p \$PID_FILE $daemon"
else
    STOP_CMD="killproc $daemon"
fi

if command -v status_of_proc >/dev/null 2>&1 ; then
    STATUS_CMD="status_of_proc -p \$PID_FILE \$DAEMON \$NAME"
else
    ckstat() { ps wax | grep -v grep | grep -q $daemon ; }
    STATUS_CMD=ckstat
fi
ckdep() { ps wax | grep -v grep | grep -q \$1 ; }

if ! command -v log_daemon_msg >/dev/null 2>&1 ; then
    log_action_msg() { echo "--- " \$*; }
    log_daemon_msg() { echo "--- " \$*; }
    log_end_msg() { 
        RET=\$1; 
        if [ \$1 -eq 0 ] ; then
            echo "--- Success"
        else
            echo "*** Failed"
        fi
        return \$RET;
    }
fi

set -e
export PATH=$root/usr/local/sbin:$root/usr/local/bin:$root/sbin:$root/bin:$root/usr/sbin:$root/usr/bin

case "\$1" in
  start)
    if \$STATUS_CMD 1>/dev/null 2>&1 ; then
        echo "\$NAME already running" 1>&2
        exit 0
    fi
    $depchunk
    $prestartchunk
    log_daemon_msg "Starting   $title" "\$NAME" || true
    if \$START_CMD ; then
        log_end_msg 0 || true
    else
        log_end_msg 1 || true
    fi
    $poststartchunk
    ;;

  stop)
    if ! \$STATUS_CMD 1>/dev/null 2>&1 ; then
        echo "\$NAME already stopped" 1>&2
        exit 0
    fi
    $prestopchunk
    log_daemon_msg "Stopping $title" "\$NAME" || true
    if \$STOP_CMD; then
        log_end_msg 0 || true
    else
        log_end_msg 1 || true
    fi
    $poststopchunk
    ;;

  reload)
    log_daemon_msg "Reloading $title" "\$NAME" || true
    if start-stop-daemon --stop --signal 1 --quiet --oknodo --pidfile \$PID_FILE  --make-pidfile --exec \$DAEMON ; then
        log_end_msg 0 || true
    else
        log_end_msg 1 || true
    fi
    ;;

  restart)
    \$0 stop
    while true; do
        sleep 1
        \$STATUS_CMD 1>/dev/null 2>&1
        [ \$? -ne "0" ] && break
    done
    \$0 start
    ;;

  status)
    if \$STATUS_CMD 1>/dev/null 2>&1 ; then
        echo \$NAME is running
        exit 0
    else
        echo \$NAME is stopped
        exit 1
    fi
    ;;

  *)
    log_action_msg "Usage: $root/etc/init.d/\$NAME {start|stop|reload|restart|status}" || true
    exit 1
esac

exit 0
__EOSCRIPT__

    # Create the init file
    my $initfile = $this->{initfile} = "$root/etc/init.d/$name";
    return $this->{err} = "Service exists: $name"
        if -e $initfile && !$opts{force};
    open(IF, '>', $initfile)
        or return $this->{err} = "Cannot create init file $initfile: $!";
    print IF $script;
    close IF;
    chmod 0755, $initfile
        or return $this->{err} = "Cannot chmod 755 file $initfile: $!";

    # Enabled or started on add?
    $this->{err}     = ERR_OK;
    $this->{type}    = $type;
    $this->{running} = 0;
    $this->{on_boot} = 0;
    $this->enable() if !$this->error && $opts{name} && $opts{enable};
    $this->start()  if !$this->error && $opts{name} && $opts{start};

    return $this->{err};
}

sub disable {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_DIS(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};

    # Disable it for boot at all runlevels
    my $cmdurc = "$this->{root}/usr/sbin/update-rc.d";
    my $cmdchk = "$this->{root}/sbin/chkconfig";
    if (-x $cmdurc) {
        my $out = qx($cmdurc -f $this->{name} remove 2>&1);
        $! ||= 0;
        return $this->{err} = "Cannot clear init links for $this->{name}: $!\n\t$out" if $?;
        # The update-rc.d man page says 
        #    "The correct way to disable services is to configure the service
        #     as stopped in all runlevels in which it is started by default."
        # However, I've been undable to get it to work.  Perhaps because
        # insserv is used on the systems I tried.  Regardless,
        # just nuking the links does the trick, and because this service
        # probably was NOT installed in the usual way, we'll be OK. 
        # So don't do the below - leave it commented out:
        #  $out = qx($cmdurc $this->{name} stop 72 0 1 2 3 4 5 6 S . 2>&1);
        #  $! ||= 0;
        #  return $this->{err} = "Cannot stop init links for $this->{name}: $!\n\t$out" if $?;
    }
    elsif (-x $cmdchk) {
        my $out = qx($cmdchk --levels 0123456 $this->{name} off 2>&1) || q{};
        $! ||= 0;
        return $this->{err} = "Cannot set levels off for $this->{name}: $!\n\t$out" if $?;
        $out = qx($cmdchk --del $this->{name} 2>&1) || q{};
        $! ||= 0;
        return $this->{err} = "Cannot delete service for $this->{name}: $!\n\t$out" if $?;

    }
    else {
        return $this->{err}
            = "Cannot stop init links for $this->{name}: no update-rc.d nor chkconfig";
    }

    $this->{on_boot} = 0;
    return $this->{err} = ERR_OK;
}

sub enable {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_ENA(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};

    # Enable it for boot with the default runlevels
    my $cmdurc = "$this->{root}/usr/sbin/update-rc.d";
    my $cmdchk = "$this->{root}/sbin/chkconfig";
    if (-x $cmdurc) {
        my $out = qx($cmdurc $this->{name} defaults 28 72 2>&1);
        $! ||= 0;
        return $this->{err} = "Cannot add init links for $this->{name}: $!\n\t$out" if $?;
    }
    elsif (-x $cmdchk) {
        my $out = qx($cmdchk --add $this->{name} 2>&1) || q{};
        $! ||= 0;
        return $this->{err} = "Cannot add service for $this->{name}: $!\n\t$out" if $?;
        $out = qx($cmdchk --level 2345 $this->{name} on 2>&1) || q{};
        $! ||= 0;
        return $this->{err} = "Cannot set levels on for $this->{name}: $!\n\t$out" if $?;
    }
    else {
        return $this->{err}
            = "Cannot add init links for $this->{name}: no update-rc.d nor chkconfig";
    }

    $this->{on_boot} = 1;
    return $this->{err} = ERR_OK;
}

sub load {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_LOAD(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};
    my $name = $this->{name};

    # Reset everything
    $this->{name}     = $name;
    $this->{title}    = q{};
    $this->{type}     = 'simple';
    $this->{prerun}   = [];
    $this->{runcmd}   = q{};
    $this->{postrun}  = [];
    $this->{prestop}  = [];
    $this->{poststop} = [];
    $this->{depends}  = [];
    $this->{running}  = 0;
    $this->{on_boot}  = 0;

    # Parse the init file
    my $initfile = $this->{initfile} = "$this->{root}/etc/init.d/$name";
    open(UF, '<', $initfile)
        or return $this->{err} = "No such service $name: cannot open $initfile: $!";
    my $inprerun   = 0;
    my $inpostrun  = 0;
    my $inprestop  = 0;
    my $inpoststop = 0;
    my $daemon     = q{};
    my $dopts      = q{};
    while (my $line = <UF>) {

        if ($line =~ m{^\s*#\s*BEGIN\s+PRE-START\s*$}i) {
            $inprerun = 1;
            next;
        }
        if ($inprerun) {
            if ($line =~ m{^\s*#\s*END\s+PRE-START\s*$}i) {
                $inprerun = 0;
            }
            else {
                chomp $line;
                $line =~ s{^\s{4}}{};
                push @{$this->{prerun}}, $line;
            }
            next;
        }

        if ($line =~ m{^\s*#\s*BEGIN\s+POST-START\s*$}i) {
            $inpostrun = 1;
            next;
        }
        if ($inpostrun) {
            if ($line =~ m{^\s*#\s*END\s+POST-START\s*$}i) {
                $inpostrun = 0;
            }
            else {
                chomp $line;
                $line =~ s{^\s{4}}{};
                push @{$this->{postrun}}, $line;
            }
            next;
        }

        if ($line =~ m{^\s*#\s*BEGIN\s+PRE-STOP\s*$}i) {
            $inprestop = 1;
            next;
        }
        if ($inprestop) {
            if ($line =~ m{^\s*#\s*END\s+PRE-STOP\s*$}i) {
                $inprestop = 0;
            }
            else {
                chomp $line;
                $line =~ s{^\s{4}}{};
                push @{$this->{prestop}}, $line;
            }
            next;
        }

        if ($line =~ m{^\s*#\s*BEGIN\s+POST-STOP\s*$}i) {
            $inpoststop = 1;
            next;
        }
        if ($inpoststop) {
            if ($line =~ m{^\s*#\s*END\s+POST-STOP\s*$}i) {
                $inpoststop = 0;
            }
            else {
                chomp $line;
                $line =~ s{^\s{4}}{};
                push @{$this->{poststop}}, $line;
            }
            next;
        }

        $this->{title} = $1 if $line =~ m{^\s*#\s*short-description:\s+(.+?)\s*$}i;
        $this->{type}  = $1 if $line =~ m{^\s*TYPE=\s*(.+?)\s*$};
        $dopts         = $1 if $line =~ m{^\s*DOPTS=\s*\'?(.*?)\'?\s*$};
        $daemon        = $1 if $line =~ m{^\s*DAEMON=\s*(.+?)\s*$};
        $this->{depends} = [split(/\s+/, $1)] if $line =~ m{^\s*#\s*Depends:\s+(.+?)\s*$}i;
    }
    $dopts =~ s{'"('+)"'}{$1}g; # un-do single-quote protection
    close UF;
    $this->{runcmd} = "$daemon $dopts";

    # Trim log message begin's & end's that we added when created
    if (   (@{$this->{prerun}} >= 2)
        && ($this->{prerun}->[0]  =~ m{^log_daemon_msg\s})
        && ($this->{prerun}->[-1] =~ m{^log_end_msg\s}))
    {
        shift @{$this->{prerun}};    # Remove first
        pop @{$this->{prerun}};      # Remove last
    }
    if (   (@{$this->{postrun}} >= 2)
        && ($this->{postrun}->[0]  =~ m{^log_daemon_msg\s})
        && ($this->{postrun}->[-1] =~ m{^log_end_msg\s}))
    {
        shift @{$this->{postrun}};    # Remove first
        pop @{$this->{postrun}};      # Remove last
    }

    # Run the init's status to see if it's running
    my $out = qx($initfile status 2>&1);
    $this->{running} = 1 if !$? && ($out =~ m{\bis\s+running}i);

    # Use update-rc.d or chkconfig to check if it's enabled at boot
    my $cmdurc = "$this->{root}/usr/sbin/update-rc.d";
    my $cmdchk = "$this->{root}/sbin/chkconfig";
    if (-x $cmdurc) {

        # We don't use the command here - but ensure it's there
        # Instead we look for start links at runlevels 2 3 4 5
        my @startlinks = glob("$this->{root}/etc/rc[2345].d/S[0-9][0-9]$name");
        $this->{on_boot} = @startlinks > 0 ? 1 : 0;
    }
    elsif (-x $cmdchk) {
        my $out = qx($cmdchk --list $name 2>&1) || q{};
        $this->{on_boot} = $out =~ m{\s[2345]\:on\b}i;
    }
    else {
        return $this->{err} = "Cannot check boot state for $name";
    }

    return $this->{err} = ERR_OK;
}

sub remove {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_REM(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};
    my $name = $this->{name};
    my $initfile = "$this->{root}/etc/init.d/$name";
    return $this->{err} = "No such service $name"
        if !-e $initfile && !$opts{force};

    # If we're removing it, we must first insure its stopped and disabled
    $this->stop();    #ignore errors except...? XXX
    $this->disable();

    # Remove links & script
    my $cmdurc   = "$this->{root}/usr/sbin/update-rc.d";
    my $cmdchk   = "$this->{root}/sbin/chkconfig";
    if (-x $cmdurc) {
        # update-rc.d : script goes first then links
        my $n = unlink $initfile;
        $! ||= 0;
        return $this->{err} = "Cannot remove service $name: $!" unless $n;
        my $out = qx($cmdurc $name remove 2>&1);
        $! ||= 0;
        return $this->{err} = "Cannot remove init links for $name: $!\n\t$out" if $?;
    }
    elsif (-x $cmdchk) {
        # chkconfig : links go first then script
        my $out = qx($cmdchk --del $name 2>&1) || q{};
        $! ||= 0;
        return $this->{err} = "Cannot remove init links for $name: $!\n\t$out" if $?;
        my $n = unlink $initfile;
        $! ||= 0;
        return $this->{err} = "Cannot remove service $name: $!" unless $n;
    }
    else {
        return $this->{err} = "Cannot remove init links for $name: no update-rc.d nor chkconfig";
    }

    # Clear all
    $this->{name}     = q{};
    $this->{prerun}   = [];
    $this->{runcmd}   = q{};
    $this->{postrun}  = [];
    $this->{prestop}  = [];
    $this->{poststop} = [];
    $this->{depends}  = [];
    $this->{title}    = q{};
    $this->{type}     = q{};
    $this->{initfile} = q{};
    $this->{running}  = 0;
    $this->{on_boot}  = 0;
    return $this->{err} = ERR_OK;
}

sub start {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_START(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};
    my $name = $this->{name};

    # Run the init's own start command
    my $initfile = $this->{initfile} = "$this->{root}/etc/init.d/$name";
    my $out = qx($this->{initfile} start 2>&1);
    $! ||= 0;
    return $this->{err} = "Cannot start $name: $!\n\t$out"
        if $?;
    $this->{running} = 1;
    return $this->{err} = ERR_OK;
}

sub stop {
    my $this = shift;
    my %opts = $this->_ckopts(Init::Service::OPTS_STOP(), @_);
    return $this->{err} if $this->{err};
    return $this->{err} = "Missing service name" unless $this->{name};
    my $name = $this->{name};

    # Run the init's own stop command
    my $initfile = $this->{initfile} = "$this->{root}/etc/init.d/$name";
    my $out = qx($this->{initfile} stop 2>&1);
    $! ||= 0;
    return $this->{err} = "Cannot stop $name: $!\n\t$out"
        if $?;
    $this->{running} = 0;
    return $this->{err} = ERR_OK;
}

1;

__END__

=head1 NAME

Init::Service - Manage system init services - SysV, upstart, systemd

=head1 VERSION

Version 2017.03.13

=head1 SYNOPSIS

Regardless of whether you use SysV, upstart, or systemd as your init system,
this module makes it easy to add/remove, enable/disable for boot, start/stop,
and check status on your system services.  It's essentially a wrapper around
each of the corresponding init system's equivalent functionality.

    use v5.10.0;
    use Init::Service;
    my $svc = Init::Service->new();

    # Show the underlying init system
    say $svc->initsys;

    # Load an existing service, to get info or check state
    my $err = $svc->load("foo-service");
    if ($err) { ... }
       # --or--
    $svc = Init::Service->new(name => "foo-service");

    # Print service info
    say $svc->name;
    say $svc->type;
    say $svc->runcmd;
    say $svc->enabled? "Enabled" : "Disabled";
    say $svc->running? "Running" : "Stopped";

    # Make new service known to the system (creates .service, .conf, or /etc/init.d file)
    $err = $svc->add(name   => "foo-daemon",
                     runcmd => "/usr/bin/foo-daemon -D -p1234");
       # --or--
    $svc = Init::Service->new( ...same args...)
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

    my $svc = new Init::Service();
    if ($svc->error) { ... }

With at least both I<name> and I<runcmd> passed, creates a new service on the system.
This is the same as calling an empty new() then calling add() with those arguments.

    my $svc = new Init::Service(name   => 'foo-daemon',
                                runcmd => '/usr/bin/foo-daemon -D -p1234');
    if ($svc->error) { ... }

When called with I<name> but NOT I<runcmd>, it will attempt to load() an existing service, if any.

    my $svc = new Init::Service(name => 'foo-daemon');
    if ($svc->error) { ... }

Takes the same arguments as I<add()>.
Remember to check the object for an error after creating it.

=head2 C<depends>

Returns a LIST of the depended-upon service names.
Remember to call this in list context!

=head2 C<prerun>

Returns a LIST of the pre-run command(s) defined for the service.
For systemd, this is I<ExecStartPre>.
For upstart, this is I<pre-start exec> or the I<pre-start script> section.
For SysVinit, these are pre-commands within the /etc/init.d script.
Remember to call this in list context!

=head2 C<runcmd>

Returns the run command defined for the service.
For systemd, this is I<ExecStart>.
For upstart, this is I<exec>.
For SysVinit, these is the one main daemon command within the /etc/init.d script.
This always returns a single command string; call this in scalar context.

Note - this does not 'run' the service now; it's just an accessor to
return what's defined to be run.  To start the service now, use C<start()>.

=head2 C<postrun>

Returns a LIST of the post-run command(s) defined for the service.
For systemd, this is I<ExecStartPost>.
For upstart, this is I<post-start exec> or the I<post-start script> section.
For SysVinit, these are the post-commands within the /etc/init.d script.
Remember to call this in list context!

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

Returns the name of the init system style we'll in use.

Note that this is the style we'll work with, not necessarily the 
actual init system that was run at startup.  For example, older 
versions of upstart (<0.6) only knew how to run SysVinit scripts;
for those we'll use SysVinit scripts even though upstart is running.

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

You must provide at least the I<name> and I<runcmd> arguments to add a new service.

    $svc->add(name    => "foo-service",           # Required identifier for service
              title   => "Handles foo requests",  # Optional description
              prerun  => ["/bin/foo-prep -a"],    # Optional pre-start command(s)
              runcmd  => "/bin/foo-daemon -D",    # Required command(s) to run the service
              postrun => ["/bin/foo-fix -x"],     # Optional post-start command(s)
              prestop => ["/bin/echo bye"],       # Optional pre-stop command(s)
              poststop => ["bin/rm /tmp/t3*"],    # Optional post-stop command(s)
              depends => [$service1, $svc2],      # Optional list of prerequisite services
              enable  => 1,                       # Optional, enable to start at boot
              start   => 1,                       # Optional, start the service now
             );
    if ($svc->error) {
        die "*** Cannot add service: " . $svc->error;
    }

The service name must be a simple identifier, consisting only of alphanumeric characters,
dash "-", dot ".", underscore "_", colon ":", or the at-sign "@".
The maximum length is 64 characters.

The prerun, runcmd, postrun, prestop, and poststop commands MUST use absolute
paths to the executable.  The C<runcmd> must be only a single command, and is
passed as a scalar string.  The others -- prerun, postrun, prestop, poststop
-- accept multiple commands.  Whether one command or multiple, they must be
passed as an array ref:

              prerun => ["/bin/bar-blue -x3"]           # Single command
              prerun => ["/bin/foo-red -a 2",
                         "/bin/foo-daemon -D -p1234"]   # Two commands

Note: You cannot (yet) specify a shell script for any of the command options.
They must be individual executables.  Script snippets are planned for the
future.

Dependent services you specify must be running already before this service
can start, and if any of those are stopped then this service will be stopped
first.  An errant stop of a dependent service, such as if it is killed,
is not detected by the 'depends' logic and won't affect this service directly.

The dependent services also imply startup and shutdown order: this service will
start (if enabled) after the dependent services, and shutdown before them.

To un-do an C<add()>, use C<remove()>.

=head2 C<disable>

Disables the service so that it will not start at boot.  This is the opposite of C<enable>.
This does not affect a running service instance; it only affects what happens at boot-time.

The reverse of C<disable()> is C<enable()>.

=head2 C<enable>

Enables the service so that it will start at boot.  This is the opposite of C<disable>.
This does not affect a stopped service instance; it only affects what happens at boot-time.

The reverse of C<enable()> is C<disable()>.

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

To use this function, either provide the name of the service, or you must add() or load() it first.

=head1 AUTHOR

Uncle Spook, C<< <spook at MisfitMountain.org> >>

=head1 BUGS & SUPPORT

Please report any bugs or feature requests via the GitHub issue
tracker at https://github.com/spook/init-service/issues .

You can find documentation for this module with the perldoc command.

    perldoc Init::Service

or via its man pages:

    man init-service        # for the command line interface
    man Init::Service       # for the Perl module

=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

This program is released under the following license: MIT

Copyright 2017 Uncle Spook.
See https://github.com/spook/init-service

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software
is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

=cut

