# Base Interface Classes #

This tree holds generic definitions of standard interfaces, often with
embedded debug logging for simulation. The interfaces may be instantiated in
multiple contexts. For example, an Avalon interface may be used either for
local memory and for host channels.

Generic modules, such as clock crossing bridges, may also be present.

## Port Naming ##

Ports are typically named for the direction of the endpoint to which they
connect, e.g.: "to_master" and "to_slave". This seems unnecessarily
complicated for simple cases such as a master connected directly to a
slave. Consider, however, the naming of ports inside a shim that has two
ports: one in the direction of the master and one in the direction of the
slave. The shim's "slave" port would be on the master side and the shim's
"master" port would be on the slave side.  With "to_" naming, a shim's
"to_master" connects to the master. The endpoints are also consistent: the
master's outgoing port is named "to_slave" and the slave's outgoing port is
named "to_master".
