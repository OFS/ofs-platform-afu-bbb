# Base Interface Classes #

This tree holds generic definitions of standard interfaces, often with
embedded debug logging for simulation. The interfaces may be instantiated in
multiple contexts. For example, an Avalon interface may be used either for
local memory and for host channels.

Generic modules, such as clock crossing bridges, may also be present.

## Port Naming ##

Ports are typically named for the direction of the endpoint to which they
connect, e.g.: "to_source" and "to_sink". This seems unnecessarily
complicated for simple cases such as a source connected directly to a
sink. Consider, however, the naming of ports inside a shim that has two
ports: one in the direction of the source and one in the direction of the
sink. The shim's "sink" port would be on the source side and the shim's
"source" port would be on the sink side.  With "to_" naming, a shim's
"to_source" connects to the source. The endpoints are also consistent: the
source's outgoing port is named "to_sink" and the sink's outgoing port is
named "to_source".
