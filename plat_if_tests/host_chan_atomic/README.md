The PIM currently supports atomic host channel requests only when requesting AXI-MM
encoding. Of course, the underlying host channel must also support atomic transactions.
The PCIe SS on Agilex supports atomic requests. No S10 OFS or PAC systems have atomics
enabled.

The PIM's AXI-MM encoding for atomic requests is available on all systems, independent
of whether they actually work. The Verilog macro OFS\_PLAT\_PARAM\_HOST\_CHAN\_ATOMICS
is defined on all platforms with working atomics support once ofs\_plat\_if.vh is
included.

The PIM's AXI-MM atomic request encoding follows the AMBA AXI5 standard as defined in
section E1.1 of the AMBA AXI specification. Only the subset that works on PCIe is
supported: fetch-add, swap and compare-and-swap (CAS). Operand sizes of 4 and 8 bytes
are supported. For CAS, this means the compare and swap values are each either 4 or 8
bytes and the full request payload is 8 or 16 bytes. Any naturally aligned address
is supported - either to 4 or 8 bytes. Only AWLEN of 0 is permitted.

As defined by AXI5:

* Requests are sent on the AW and W channels.
* Responses are returned on the B (write commit) and R (read response) channels.
* The ID sent on AW is returned with both the B and R responses.
* For CAS, the relative order of the compare and swap values on W follows the AXI5
specification. The full CAS value is naturally aligned for the size of both values, to
either 8 or 16 bytes. The compare argument is always passed at the position matching
the target address.
* AWSIZE and AWBURST must follow the table in E1.1.3, though AWBURST is ignored by the PIM.

When the PIM is configured to sort read responses, atomic read responses are also
sorted in request order. Otherwise, response order depends on the underlying hardware's
behavior.
