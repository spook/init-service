# NAME

Init::Service - Manage system init services - SysV, upstart, systemd

# VERSION

Version 2017.03.13

# SYNOPSIS

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

# SUBROUTINES/METHODS

## `new`

Constructor.
With no arguments, it determines the type of init system in use, and creates an empty service
object, which can later be add()'d or load()'d.

    my $svc = new Init::Service();
    if ($svc->error) { ... }

With at least both _name_ and _runcmd_ passed, creates a new service on the system.
This is the same as calling an empty new() then calling add() with those arguments.

    my $svc = new Init::Service(name   => 'foo-daemon',
                                runcmd => '/usr/bin/foo-daemon -D -p1234');
    if ($svc->error) { ... }

When called with _name_ but NOT _runcmd_, it will attempt to load() an existing service, if any.

    my $svc = new Init::Service(name => 'foo-daemon');
    if ($svc->error) { ... }

Takes the same arguments as _add()_.
Remember to check the object for an error after creating it.

## `depends`

Returns a LIST of the depended-upon service names.
Remember to call this in list context!

## `prerun`

Returns a LIST of the pre-run command(s) defined for the service.
For systemd, this is _ExecStartPre_.
For upstart, this is _pre-start exec_ or the _pre-start script_ section.
For SysVinit, these are pre-commands within the /etc/init.d script.
Remember to call this in list context!

## `runcmd`

Returns the run command defined for the service.
For systemd, this is _ExecStart_.
For upstart, this is _exec_.
For SysVinit, these is the one main daemon command within the /etc/init.d script.
This always returns a single command string; call this in scalar context.

Note - this does not 'run' the service now; it's just an accessor to
return what's defined to be run.  To start the service now, use `start()`.

## `postrun`

Returns a LIST of the post-run command(s) defined for the service.
For systemd, this is _ExecStartPost_.
For upstart, this is _post-start exec_ or the _post-start script_ section.
For SysVinit, these are the post-commands within the /etc/init.d script.
Remember to call this in list context!

## `enabled`

Returns a true/false value that indicates if the service is enabled to start at boot.

## `error`

Returns the current error status string for the service.
If no error (all is OK), returns an empty string which evaluates to false.
The normal way to use this is like:

    $svc->some_function(...);
    if ($svc->error) { ...handle error... }

## `initfile`

Returns the filename of the unit file, job file, or init script
used to start the service.

## `initsys`

Returns the name of the init system style we'll in use.

Note that this is the style we'll work with, not necessarily the 
actual init system that was run at startup.  For example, older 
versions of upstart (<0.6) only knew how to run SysVinit scripts;
for those we'll use SysVinit scripts even though upstart is running.

Possible values are 'unknown', 'SysVinit', 'upstart', or 'systemd'.

## `name`

Returns the service name.

## `running`

Returns true/false to indicate if the service is currently running.

## `title`

Returns a string that describes the service.
For systed, this is the _Description_ option.
For upstart, this is the _description_ stanza.
For SysVinit, this is the _Short-Description_ in the LSB header.

## `type`

Returns the service type.
Possibe values are simple, forking, notify, or oneshot.
For upstart, these are the mappings:

- 'simple' is the job type 'service' without an 'expect' stanza;
- 'oneshot' is the jopb type 'task' without an 'expect' stanza;
- 'forking' is the job type 'task' with 'expect daemon' stanza;
- 'notify' is the job type 'task' with 'expect stop' stanza.

For SysVinit, these service types are simulated.

## `add`

Adds a new service to the system.
Must be run as the root user.
This funciton will create necessary unit file, job file, or init script(s) on the system.
If the service already exists, an error is returned.
By default, the service is not started nor enambed for boot.

You must provide at least the _name_ and _runcmd_ arguments to add a new service.

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
dash "-", dot ".", underscore "\_", colon ":", or the at-sign "@".
The maximum length is 64 characters.

The prerun, runcmd, postrun, prestop, and poststop commands MUST use absolute
paths to the executable.  The `runcmd` must be only a single command, and is
passed as a scalar string.  The others -- prerun, postrun, prestop, poststop
\-- accept multiple commands.  Whether one command or multiple, they must be
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

To un-do an `add()`, use `remove()`.

## `disable`

Disables the service so that it will not start at boot.  This is the opposite of `enable`.
This does not affect a running service instance; it only affects what happens at boot-time.

The reverse of `disable()` is `enable()`.

## `enable`

Enables the service so that it will start at boot.  This is the opposite of `disable`.
This does not affect a stopped service instance; it only affects what happens at boot-time.

The reverse of `enable()` is `disable()`.

## `load`

Load the definition and status for the given service name.  Example:

    $svc->load("foo-service");
    if ($svc->error) { ... }
    say $svc->running ? "Foo is alive" : "Foo is not running";

## `remove`

Removes the service definition from the system; this makes the service unknown.
Any unit files, job files, or init scripts will be deleted.
If the service is running, it will be stopped first.
If the service is enabled for boot, it will be disabled.

To use this function, either provide the name of the service, or you must add() or load() it first.

# AUTHOR

Uncle Spook, `<spook at MisfitMountain.org>`

# BUGS & SUPPORT

Please report any bugs or feature requests via the GitHub issue
tracker at https://github.com/spook/init-service/issues .

You can find documentation for this module with the perldoc command.

    perldoc Init::Service

or via its man pages:

    man init-service        # for the command line interface
    man Init::Service       # for the Perl module

# ACKNOWLEDGEMENTS

# LICENSE AND COPYRIGHT

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
