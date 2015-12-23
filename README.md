# service
Enhances the 'service' command to support the "big three" inits: SystemV, upstart, and systemd; 
PLUS handles install, remove actions too.

# Functions
As today:
* start
* stop
* restart
* reload
* force-reload
* status
* --status-all
New:
* enable - Mark a service to be started at boot; does not affect current state
* disable - Make service not start at boot; does not affect current state
* install - Make the service known to the system; puts the approproate script/stanza in place
* remove - Makes the service unknown to the system; will do a stop and disable first, then removes the appropriate script/stanza



