# service
Enhances the 'service' command to support the "big three" inits: SystemV, upstart, and systemd; 
PLUS handles install, remove actions too.

# Functions
As today:
* start -
Runs the service; if already running, an error is emitted
* stop -
Stops a running service; if not running, an error is emitted
* restart -
Stops then starts a service
* reload -
Sends a SIGHUP to the service, if runninggg
* status -
Displays the status of the service
* --status-all

New functions:
* enable - 
Mark a service to be started at boot; does not affect current state
* disable - 
Make service not start at boot; does not affect current state
* install - 
Make the service known to the system; puts the approproate script/stanza in place.
Usually only the package's installer script uses this command.
* remove - 
Makes the service unknown to the system; will do a stop and disable first, 
then removes the appropriate script/stanza
Usually only the package's remove script uses this command.

# Function Options
## Auto-restart Watchdog
This has upstart or systemd watch the service, and automatically restart it
if the service dies.  Not available under SysVinit.

# How Implemented in each init

## start
If -r /etc/systemd/service/${SERVICE}.service,
then exec systemctl start ${SERVICE}

If -r /etc/init/${SERVICE}.conf, then we have an upstart for it, 
so exec the start command on the service and any options

If -r /etc/init.d/${SERVICE}, then SystemV, 
so exec that with "start" and options

## stop
Similar to start

## restart
Similar to start

## reload
Similar to start

## enable
TBS

## disable
TBS

## install
Basic idea: 
        service xyz install \
            -V path/to/sysVinit/script \
            -U path/to/upstart/stanzas \
            -W path/to/systemd/unitfile
It then puts one of the given files into the right places, 
selecting the appropriate one for the init system in use.
If these init files are not provided, or the needed file
is not given for the init system in use,
it will synthesize an init scritp/stanza/unit and put it
into place.  As a minimum, the executable command
is needed:
        service xyz install -c /usr/bin/xyz -D -v

**To be worked out:**
Does -c take everything to the EOL as
options for the command, or must we quote it like this:
        service xyz install -c '/usr/bin/xyz -D -v'
or do we go with args options:
        service xyz install -c /usr/bin/xyz --arg -D --arg -v
I'm leaning towards the first method; which is as-if one entered:
        service xyz install -c /usr/bin/xyz -- -D -v
(note the --'s), or even without the -c: any left-over args are the command and its options:
        service xyz install /usr/bin/xyz -D -v
        service xyz install -d "My XYZ service" --restart /usr/bin/xyz -D -v
This is kinda how the `mkjob` command works.  I'll try it this way and see how it works out.

## remove

First `stop`, then `disable`.
This is easier than `start`, 'cuz I can simply look in the three places for the
init script/stanza/unit file and nuke them.

