package Init::Service;

use 5.8.0;
use strict;
use warnings;

our $VERSION = '2017.03.13';

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
    $this->add()  if $opts{name} &&  $opts{runcmd};
    $this->load() if $opts{name} && !$opts{runcmd};

    # Enabled or started on new?
    $this->enable() if !$this->error && $opts{name} && $opts{enable};
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
            $this->{err} = "$func: bad option $k";
            return ();
        }
        if ((ref($vops->{$k}) eq "CODE") && (my $err = $vops->{$k}->(\$v))) {
            $this->{err} = "$func: bad value for $k: $err";
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

# Unknown initsys always returns the error set in the constructor
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
    my $name    = $this->{name};
    my $title   = $this->{title};
    my $type    = $this->{type} || "simple";
    my $prerun  = $this->{prerun};
    my $runcmd  = $this->{runcmd};
    my $postrun = $this->{postrun};
    return $this->{err} = "Missing options; name and runcmd required"
        if !$name || !$runcmd;

    # Create unit file
    my $initfile = $this->{initfile} = "$this->{root}/lib/systemd/system/$name.service";
    return $this->{err} = "Service exists: $name"
        if -e $initfile && !$opts{force};
    open(UF, '>', $initfile)
        or return $this->{err} = "Cannot create init file $initfile: $!";
    print UF "[Unit]\n";
    print UF "Description=$title\n";
    print UF "After=network.target syslog.target\n";

    print UF "\n";
    print UF "[Service]\n";
    foreach my $cmd (@$prerun) {
        print UF "ExecStartPre=$cmd\n";
    }
    print UF "ExecStart=$runcmd\n";
    foreach my $cmd (@$postrun) {
        print UF "ExecStartPost=$cmd\n";
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
    $this->{running}  = 0;
    $this->{on_boot}  = 0;
    $this->{initfile} = "$this->{root}/lib/systemd/system/$name.service";

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
    my $initfile = "$this->{root}/lib/systemd/system/$name.service";
    return $this->{err} = "No such service $name"
        if !-e $initfile && !$opts{force};
    my $n = unlink $initfile;
    return $this->{err} = "Cannot remove service $name: $!" unless $n;

    # Clear all
    $this->{name}     = q{};
    $this->{prerun}   = [];
    $this->{runcmd}   = q{};
    $this->{postrun}  = [];
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
    my $name    = $this->{name};
    my $title   = $this->{title};
    my $type    = $this->{type} || "simple";
    my $prerun  = $this->{prerun};
    my $runcmd  = $this->{runcmd};
    my $postrun = $this->{postrun};
    return $this->{err} = "Missing options; name and runcmd required"
        if !$name || !$runcmd;

    # Create conf file
    my $initfile = $this->{initfile} = "$this->{root}/etc/init/$name.conf";
    return $this->{err} = "Service exists: $name"
        if -e $initfile && !$opts{force};
    open(UF, '>', $initfile)
        or return $this->{err} = "Cannot create init file $initfile: $!";
    print UF "# upstart init script for the $name service\n";
    print UF "description  \"$title\"\n";
    print UF "pre-start script\n" if @$prerun;
    foreach my $cmd (@$prerun) {
        print UF "    $cmd\n";
    }
    print UF "end script\n" if @$prerun;
    print UF "exec $runcmd\n";
    print UF "post-start script\n" if @$postrun;
    foreach my $cmd (@$postrun) {
        print UF "    $cmd\n";
    }
    print UF "end script\n"    if @$postrun;
    print UF "expect fork\n"   if $type eq "BLAHBLAHTBD";    # TODO what to use here?
    print UF "expect daemon\n" if $type eq "forking";
    print UF "expect stop\n"   if $type eq "notify";
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

    # Inhale the file line by line, removing any existing start on / stop on clauses
    my $contents = q{};
    my $initfile = $this->{initfile} || "$this->{root}/etc/init/$name.conf";
    open(UF, '<', $initfile)
        or return $this->{err} = "Cannot open unit file $initfile: $!";
    while (my $line = <UF>) {
        next if $line =~ m{^\s*start\b}i;
        next if $line =~ m{^\s*stop\b}i;
        $contents .= $line;
    }
    close UF;

    # If we want to be enabled, add those clauses
    if ($enable) {
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
    $this->{name}    = $name;
    $this->{title}   = q{};
    $this->{type}    = 'simple';
    $this->{prerun}  = [];
    $this->{runcmd}  = q{};
    $this->{postrun} = [];
    $this->{running} = 0;
    $this->{on_boot} = 0;

    # Parse the init file
    my $initfile = $this->{initfile} = "$this->{root}/etc/init/$name.conf";
    open(UF, '<', $initfile)
        or return $this->{err} = "No such service $name: cannot open $initfile: $!";
    my $inpre  = 0;
    my $inpost = 0;
    while (my $line = <UF>) {
        if ($line =~ m{^\s*pre-start\s+exec\s+(.+)$}i) {
            push @{$this->{prerun}}, $1;
            next;
        }
        if ($line =~ m{^\s*pre-start\s+script\s*$}i) {
            $inpre = 1;
            next;
        }
        if ($inpre) {
            if ($line =~ m{^\s*end\s+script\s*$}i) {
                $inpre = 0;
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
            $inpost = 1;
            next;
        }
        if ($inpost) {
            if ($line =~ m{^\s*end\s+script\s*$}i) {
                $inpost = 0;
            }
            else {
                chomp $line;
                $line =~ s{^\s{4}}{};
                push @{$this->{postrun}}, $line;
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

    # then also run `service $name status` to read current state
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
    return $this->{err} = "Cannot remove service $name: $!" unless $n;

    # Clear all
    $this->{name}     = q{};
    $this->{prerun}   = [];
    $this->{runcmd}   = q{};
    $this->{postrun}  = [];
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

    my $out = qx(stop $name 2>&1);
    return $this->{err} = "Cannot stop $name: $!\n\t$out"
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
    my $root    = $this->{root} || q{};
    my $name    = $this->{name};
    my $title   = $this->{title};
    my $type    = $this->{type} || "simple";
    my $prerun  = $this->{prerun};
    my $runcmd  = $this->{runcmd};
    my $postrun = $this->{postrun};
    return $this->{err} = "Missing options; name and runcmd required"
        if !$name || !$runcmd;

    my ($daemon, $opts) = $runcmd =~ m/^\s*(\S+)\s+(.+)$/;
    my $bgflag_ub = ($type eq "simple") || ($type eq "notify") ? "--background" : q{};
    my $bgflag_rh = ($type eq "simple") || ($type eq "notify") ? "&"            : q{};

    my $prechunk = q{};
    if (@$prerun) {
        $prechunk
            = "\n    log_daemon_msg \"Pre-Start  $title\" \"$name\" || true"
            . "\n    "
            . join("\n    ", @$prerun)
            . "\n    log_end_msg 0 || true";
    }
    my $postchunk = q{};
    if (@$postrun) {
        $postchunk
            = "\n    log_daemon_msg \"Post-Start $title\" \"$name\" || true"
            . "\n    "
            . join("\n    ", @$postrun)
            . "\n    log_end_msg 0 || true";
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

set +e
umask 022

TYPE=$type
NAME=$name
DOPTS="$opts"
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
    START_CMD="start-stop-daemon --start --quiet --oknodo --pidfile \$PID_FILE $bgflag_ub --exec \$DAEMON -- \$DOPTS"
else
    echo "*** init functions not available" 1>&2
    exit 5
fi
STOP_CMD="killproc -p \$PID_FILE $daemon"

if command -v status_of_proc >/dev/null 2>&1 ; then
    STATUS_CMD="status_of_proc -p \$PID_FILE \$DAEMON \$NAME"
else
    ckstat() { ps wax | grep -v grep | grep -q -1 $daemon ; }
    STATUS_CMD=ckstat
fi

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
    # BEGIN PRE-START$prechunk
    # END PRE-START
    log_daemon_msg "Starting   $title" "\$NAME" || true
    if \$START_CMD ; then
        log_end_msg 0 || true
    else
        log_end_msg 1 || true
    fi
    # BEGIN POST-START$postchunk
    # END POST-START
    ;;

  stop)
    log_daemon_msg "Stopping $title" "\$NAME" || true
    if \$STOP_CMD; then
        log_end_msg 0 || true
    else
        log_end_msg 1 || true
    fi
    ;;

  reload)
    log_daemon_msg "Reloading $title" "\$NAME" || true
    if start-stop-daemon --stop --signal 1 --quiet --oknodo --pidfile \$PID_FILE --exec \$DAEMON ; then
        log_end_msg 0 || true
    else
        log_end_msg 1 || true
    fi
    ;;

  restart)
    \$0 stop
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
        return $this->{err} = "Cannot clear init links for $this->{name}: $!\n\t$out" if $?;
        $out = qx($cmdurc $this->{name} stop 72 0 1 2 3 4 5 6 S . 2>&1);
        return $this->{err} = "Cannot stop init links for $this->{name}: $!\n\t$out" if $?;
    }
    elsif (-x $cmdchk) {
        my $out = qx($cmdchk --levels 0123456 $this->{name} off 2>&1) || q{};
        return $this->{err} = "Cannot set levels off for $this->{name}: $!\n\t$out" if $?;
        $out = qx($cmdchk --del $this->{name} 2>&1) || q{};
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
        return $this->{err} = "Cannot add init links for $this->{name}: $!\n\t$out" if $?;
    }
    elsif (-x $cmdchk) {
        my $out = qx($cmdchk --add $this->{name} 2>&1) || q{};
        return $this->{err} = "Cannot add service for $this->{name}: $!\n\t$out" if $?;
        $out = qx($cmdchk --level 2345 $this->{name} on 2>&1) || q{};
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
    $this->{name}    = $name;
    $this->{title}   = q{};
    $this->{type}    = 'simple';
    $this->{prerun}  = [];
    $this->{runcmd}  = q{};
    $this->{postrun} = [];
    $this->{running} = 0;
    $this->{on_boot} = 0;

    # Parse the init file
    my $initfile = $this->{initfile} = "$this->{root}/etc/init.d/$name";
    open(UF, '<', $initfile)
        or return $this->{err} = "No such service $name: cannot open $initfile: $!";
    my $inpre  = 0;
    my $inpost = 0;
    my $daemon = q{};
    my $dopts  = q{};
    while (my $line = <UF>) {

        if ($line =~ m{^\s*#\s*BEGIN\s+PRE-START\s*$}i) {
            $inpre = 1;
            next;
        }
        if ($inpre) {
            if ($line =~ m{^\s*#\s*END\s+PRE-START\s*$}i) {
                $inpre = 0;
            }
            else {
                chomp $line;
                $line =~ s{^\s{4}}{};
                push @{$this->{prerun}}, $line;
            }
            next;
        }
        if ($line =~ m{^\s*#\s*BEGIN\s+POST-START\s*$}i) {
            $inpost = 1;
            next;
        }
        if ($inpost) {
            if ($line =~ m{^\s*#\s*END\s+POST-START\s*$}i) {
                $inpost = 0;
            }
            else {
                chomp $line;
                $line =~ s{^\s{4}}{};
                push @{$this->{postrun}}, $line;
            }
            next;
        }
        $this->{title} = $1 if $line =~ m{^\s*#\s*short-description:\s+(.+?)\s*$}i;
        $this->{type}  = $1 if $line =~ m{^\s*TYPE=\s*(.+?)\s*$};
        $dopts         = $1 if $line =~ m{^\s*DOPTS=\s*\"?(.+?)\"?\s*$};
        $daemon        = $1 if $line =~ m{^\s*DAEMON=\s*(.+?)\s*$};
    }
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
        return $this->{err} = "Cannot remove service $name: $!" unless $n;
        my $out = qx($cmdurc $name remove 2>&1);
        return $this->{err} = "Cannot remove init links for $name: $!\n\t$out" if $?;
    }
    elsif (-x $cmdchk) {
        # chkconfig : links go first then script
        my $out = qx($cmdchk --del $name 2>&1) || q{};
        return $this->{err} = "Cannot remove init links for $name: $!\n\t$out" if $?;
        my $n = unlink $initfile;
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

You must provide at least the I<name> and I<runcmd> arguments to add a new service.

    $svc->add(name    => "foo-service",           # Required identifier for service
              title   => "Handles foo requests",  # Optional description
              prerun  => "/bin/foo-prep -a",      # Optional pre-start command(s)
              runcmd  => "/bin/foo-daemon -D",    # Required command(s) to run the service
              postrun => "/bin/foo-fix -x",       # Optional post-start command(s)
              enable  => 1,                       # Optional, enable to start at boot
              start   => 1,                       # Optional, start the service now
             );
    if ($svc->error) {
        die "*** Cannot add service: " . $svc->error;
    }

The service name must be a simple identifier, consisting only of alphanumeric characters,
dash "-", dot ".", underscore "_", colon ":", or the at-sign "@".
The maximum length is 64 characters.

The prerun, runcmd, and postrun commands MUST use absolute paths to the executable.
Multiple commands can be specified for prerun and postrun -- but not C<runcmd> -- by passing an arrayref:

              prerun => ["/bin/foo-red -a 2",
                         "/bin/foo-daemon -D -p1234"]

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
tracker at https://github.com/spook/service/issues .

You can find documentation for this module with the perldoc command.

    perldoc Init::Service

or via its man pages:

    man init-service        # for the command line interface
    man Init::Service       # for the Perl module

=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

This program is released under the following license: MIT

Copyright 2017 Uncle Spook.
See https://github.com/spook/service

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
