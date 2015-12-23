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



