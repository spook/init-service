# init-service
Regardless of whether you use SysV, upstart, or systemd as your init system,
this command makes it easy to add/remove, enable/disable for boot, start/stop,
and check status on your system services.  

You no longer need to write init.d scripts, upstart .conf files, nor systemd
unit files!  This command handles the creation/removal of the init file for 
your service and the management of the underlying init system so your service
is started or not at boot, can be started or stopped immediately, and also to 
check status on your service. 

You must be root to use this command.
## Synopsys

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

## Functions
    start   - Runs the service; if already running, an error is emitted
    stop    - Stops a running service; if not running, an error is emitted
    restart - Stops then starts a service
    reload  - Sends a SIGHUP to the service, if running
    enable  - Mark a service start at boot; does not affect current state
    disable - Make service not start at boot; does not affect current state
    add     - Create (define) the service on the system
    remove  - Makes the service unknown to the system; will do a stop and disable first
    status  - Displays the status of the service
    is-started - Check if the service is running now
    is-enabled - Check if the service is enabled to start at boot
