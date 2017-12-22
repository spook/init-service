# init-service
Regardless of whether you use SysV, upstart, or systemd as your init system,
this utility makes it easy to add/remove, enable/disable for boot, start/stop,
and check status on your system services.  A command line and a Perl module
are included, so you can do it from the CLI, or from within your package.

You no longer need to write init.d scripts, upstart .conf files, nor systemd
unit files!  This utility handles the creation/removal of the init file for
your service and the management of the underlying init system, so your service
is started or not at boot, can be started or stopped immediately, and also to
check status on your service.

You must be root to use the command.

## Synopsys

Command Line:

    # Define (create/add) a new system service called foo-daemon
    #   Set it to start on boot and also run it right now
    init-service add foo-daemon \
        --run '/usr/bin/foo-daemon -D -p1234' \
        --enabled --start

    init-service start foo-daemon   # Run it now
    init-service stop  foo-daemon   # Stop it now
    init-service enable foo-daemon  # Make it start at boot
    init-service disable foo-daemon # Make it not start at boot
    init-service remove foo-daemon  # Remove it completly
    init-service status foo-daemon  # Show its status

Perl Fragment:

    use Init::Service;
        . . .
    my $service = Init::Service->new(
        name     => "thingd",
        title    => "Thing Daemon",
        runcmd   => "/usr/bin/thingd -a -b3",
    );
    if ($service->error) { ... }

## Installation

### From Source

To install this module from source, unpack the distribution,
then run the following commands:

	perl Makefile.PL
	make
	sudo make test
	sudo make install

Note that the tests are also run sudo; this is to fully test the
installation and removal of a dummy service.  If not run as root,
then only a subset of tests will be run.

### From .deb package

Install the package as you would any other Debian package:

    sudo dpkg -i init-service-XXYYZZ.deb

### From .rpm package

Install the package as you would any other RPM package:

    sudo rpm -ivh init-service-XXYYZZ.rpm

### Manual Install

There's not much to this package: a Perl module and a Perl main-program.
Look for the Init::Service module (Service.pm) and put it, with its
parent 'Init' directory in your normal Perl library location.
For example (your destination will vary):

    cp -r ./lib/Init  /usr/local/share/perl/5.22.1/
    chmod 0444 /usr/local/share/perl/5.22.1/Init/Service.pm

Then for the "main" program, the init-service script:

    cp ./bin/init-service  /usr/local/bin/
    chmod 0755 /usr/local/bin/init-service

You may also want to build the man pages from the POD at the bottom
of each of the above two files; use `pod2man` then place in the usual
locations:

    /usr/local/man/man1/init-service.1p
    /usr/local/man/man3/Init::Service.3pm


## Usage

### Command Line
```
Usage: init-service FUNCTION SVCNAME [options...]

  Functions:
    start   - Runs the service; if already running, an error is emitted
    stop    - Stops a running service; if not running, an error is emitted
    restart - Stops then starts a service
    reload  - Sends a SIGHUP to the service, if running
    enable  - Mark a service start at boot; does not affect current state
    disable - Make service not start at boot; does not affect current state
    add     - Create (define) the service on the system
    remove  - Makes service unknown to the system; will stop and disable first
    status  - Displays the status of the service
    is-running - Check if running now (use in scripts)
    is-enabled - Check if enabled at boot (use in scripts)

  General Options:
    -h --help     Show this usage help
    -v --verbose  Show more output

  Options for 'add' function:
    -r --run CMD      Command and args to run the service
    -t --type TYPE    Type of service, one of: simple forking notify oneshot
    -d --title DSC    Short description of the service
    -p --prerun CMD   Command and args to run before starting the service
    -o --postrun CMD  Command and args to run after starting the service
    -P --prestop CMD  Command and args to run before stopping the service
    -O --poststop CMD Command and args to run after stopping the service
    -e --enable       Enable the service so it starts at boot
    -s --start        Start the service now, after adding it

    -p, -o, -P, -O may be repeated for multiple commands.
```
### Perl POD

Generate the latest manpages, markdown, test, etc from the embedded POD 
in the [Init::Service](lib/Init/Service.pm) module.  For example:

    pod2markdown lib/Init/Service.pm > ./Init-Service.md
        -or-
    pod2man lib/Init/Service.pm > ./Init-Service.man

A (usually) current markdown flavor of the Perl documentation is in 
the [Init-Service.md](Init-Service.md) file along side this README.md .

## Want to help?

Would you like to contribute to this project?  I'd love the help!
First, understand the project's goals:
* init-service is NOT the be-all, end-all.  It's scope is to handle
the common, popular situations for working with simple services.
* Minimal dependencies: Currently it requires /bin/sh and core Perl modules;
eventually I want this to be shell only.  Add no dependencies please!

The best way to help is to test and fix this to work on various flavors
and versions of Linux operating systems.  To date, these are tested:
* CentOS  5.5
* CentOS  6.5
* CentOS  7.1
* Debian  5.10
* Debian  6.10
* Debian  7.11
* Debian  8.10
* Debian  9.3
* SLES   12.02
* Ubuntu  6.06
* Ubuntu  8.04
* Ubuntu 10.04
* Ubuntu 12.04
* Ubuntu 14.04
* Ubuntu 16.04
* Ubuntu 17.04

More O/S's are welcome!

This project could always use more tests, too.

For other work, look to the TODO file in the distribution.  Thanx!

-- Uncle Spook

## See Also

For something similar, see Jordan Sissel's *Please, Run!*: https://github.com/jordansissel/pleaserun
