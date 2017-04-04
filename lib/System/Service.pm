package System::Service;

use 5.006;
use strict;
use warnings;

our $VERSION = '2017.03.13';

use constant INIT_UNKNOWN => "unknown";
use constant INIT_SYSTEMV => "SysV";
use constant INIT_UPSTART => "upstart";
use constant INIT_SYSTEMD => "systemd";

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;    # Get the class name
    print "Class is $class\n";
    my $this = {
        err     => q{},             # Error status
        root    => q{},             # File-system root (blank = /)
        init    => INIT_UNKNOWN,    # Init system in use
        name    => q{},             # Service name
        type    => q{},             # Service type normal, fork, ...
        command => q{},             # Command executable and arguments
        enabled => 0,               # Will start on boot
        started => 0,               # Running now
        @_                          # Override or additional args
    };
    deduce_init_system($this);
    $this->{init} = $this->{force}        if $this->{force};
    $this->{err}  = "Unknown init system" if $this->{init} eq INIT_UNKNOWN;
    $class .= "::" . $this->{init};
    bless $this, $class;
    return $this;
}

sub deduce_init_system {
    my $this = shift;

    # Look for systemd
    my $ps_out = qx(ps -p 1 --no-headers -o comm 2>&1) || q{};    # 'comm' walks symlinks
    if (   -d "$this->{root}/lib/systemd"
        && -d "$this->{root}/etc/systemd"
        && $ps_out =~ m{\bsystemd\b})
    {
        return $this->{init} = INIT_SYSTEMD;
    }
    my $init_ver = qx($this->{root}/sbin/init --version 2>&1) || q{};
    if (-d "$this->{root}/etc/init"
        && $init_ver =~ m{\bupstart\b})
    {
        return $this->{init} = INIT_UPSTART;
    }
    if (-d "$this->{root}/etc/init.d") {
        return $this->{init} = INIT_SYSTEMV;
    }
    return $this->{init} = INIT_UNKNOWN;
}

sub command {
    return shift->{command};
}

sub error {
    return shift->{err};
}

sub init_system {
    return shift->{init};
}

sub name {
    return shift->{name};
}

sub type {
    return shift->{type};
}

#       ------- o -------
package System::Service::unknown;
our @ISA = qw/System::Service/;

sub add {
    return shift->{err};
}

sub disable {
    return shift->{err};
}

sub enable {
    return shift->{err};
}

sub load {
    return shift->{err};
}

sub remove {
    return shift->{err};
}

sub start {
    return shift->{err};
}

sub stop {
    return shift->{err};
}

#       ------- o -------
package System::Service::systemd;
our @ISA = qw/System::Service/;

sub add {
    my $this = shift;
    my %args = @_;
    my $name = $args{name};
    my $command = $args{command};
    return $this->{err} = "Insufficient argument; name and command required"
        if !$name || !$command;

    # Create unit file
    my $unitfile = "$this->{root}/lib/systemd/system/$name.service";
    return $this->{err} = "Service already exists"
        if -e $unitfile && !$args{force};

    open(UF, '>', $unitfile)
        or return $this->{err} = "Cannot create unit file: $!";
    print UF "[Unit]\n";
    print UF "Description=" . ($args{description}||q{}) . "\n";

    print UF "\n";
    print UF "[Service]\n";
    print UF "ExecStart=$command\n";
    print UF "Type=" . ($args{type}||"normal") . "\n";

    print UF "\n";
    print UF "[Install]\n";
    print UF "WantedBy=multi-user.target\n";    # TODO... how to map this?

    close UF;

    # Copy attributes into ourselves
        # TODO...

    return $this->{err} = q{};
}

sub disable {
}

sub enable {
}

sub load {
    my $this = shift;
    my $name = shift;

    my @lines = qx(systemctl show $name.service 2>&1);  # XXX Do instead? $this-{root}/bin/systemctl
    my %info = map {split(/=/, $_, 2)} @lines;
    return $this->{err} = "No such service $name" 
        if !%info || $info{LoadState} !~ m/loaded/i;
    my $cmd = $info{ExecStart};
    $cmd = $1 if $cmd =~ m{argv\[]=(.+?)\s*\;};
    $this->{name}    = $name;
    $this->{command} = $cmd;
    $this->{type}    = $info{Type};
    $this->{running} = $info{SubState} =~ m/running/i ? 1 : 0;
    $this->{enabled} = $info{UnitFileState} =~ m/enabled/i ? 1 : 0;
}

sub remove {
}

sub start {
}

sub stop {
}

#       ------- o -------
package System::Service::upstart;
our @ISA = qw/System::Service/;

sub add {
}

sub disable {
}

sub enable {
}

sub load {
}

sub remove {
}

sub start {
}

sub stop {
}

#       ------- o -------
package System::Service::SysV;
our @ISA = qw/System::Service/;

sub add {
}

sub disable {
}

sub enable {
}

sub load {
}

sub remove {
}

sub start {
}

sub stop {
}

1;

__END__

=head1 NAME

System::Service - Manage system init services

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Regardless of whether you use SysV, upstart, or systemd as your init system,
this module makes it easy to add/remove, enable/disable for boot, start, stop, and 
check status on your system services.  
It's essentially a wrapper around each of the corresponding init system's 
equivalent functionality.

    use v5.10.0;
    use System::Service;
    my $svc = System::Service->new();

    # Show the underlying init system
    say $svc->init;

    # Load an existing service
    my $err = $svc->load("foo-service");
    if ($err) { ... }
       # --or--
    $svc = System::Service->new(load => "foo-service");

    # Print service info
    say $svc->name;
    say $svc->type;
    say $svc->command;
    say $svc->enabled? "Enabled" : "Disabled";
    say $svc->running? "Running" : "Stopped";

    # Make new service known to the system (creates .service, .conf, or /etc/init.d file)
    $err = $svc->add(name => "foo-daemon",
                     command => "/usr/bin/foo-daemon -D -p123");
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

=head2 function1

=cut

sub function1 {
}

=head2 function2

=cut

sub function2 {
}

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

Copyright 2017 Uncle Spook.   https://github.com/spook/service

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=cut

