# Host Channels #

Host channels are the connection to host memory and to system MMIO spaces.
Host channels may offer both host memory and MMIO or just one type. There are
two abstraction layers in the host channel stack. One is the platform-specific
fixed interface that crosses the partial reconfiguration (PR) boundary. It
connects the FPGA Interface Unit (FIU) and the Platform Interface Manager
(PIM). This fixed layer is configured by board vendors or platform
architects. We refer to it as the *native interface*. The second layer is the
interface between PIM and the AFU. This second layer transforms the platform
interface into the protocol required by the AFU. The layer may simply be wires
if the AFU expects an interface that already matches the FIU. The layer may
also be a protocol transformation, such as Avalon to AXI. We refer to this
second layer as the *AFU interface*.

Host channels are arranged in *groups* and *ports*. A *group* is a collection
of one or more *ports*. Each port in a group must share the same configuration
(protocol, data and address widths, etc.). Groups are numbered, monotonically
increasing from zero. Host channel group zero is named *host\_chan*, group one
is *host\_chan\_g1*, group two is *host\_chan\_g2*, etc.

Host channel group 0 port 0 (plat\_ifc.host\_chan[0]) must connect to both a
host memory slave in the FIU and an MMIO master in the FIU. The MMIO space
must be the primary AFU MMIO space expected by OPAE software.

## Fixed FIU Interfaces ##

FIU interfaces are the native system interfaces exposed by the platform
logic. These interfaces cross the PR boundary and are wrapped by the Platform
Interface Manager (PIM) in the SystemVerilog interface *plat\_ifc*.

It is up to board vendors to choose the interface and protocol that crosses
the PR boundary between the FIU and the PR region. The PIM logic in this
source tree supports the following native protocols:

### CCI-P ###

The [Core Cache Interface
(CCI-P)](https://www.intel.com/content/dam/www/programmable/us/en/pdfs/literature/manual/mnl-ias-ccip.pdf)
protocol shipped as the primary host memory and MMIO protocol on Intel® FPGA
Programmable Acceleration Cards (PAC) and on some earlier integrated FPGA/CPU
prototypes.

### Avalon Memory Slave ###

The PIM supports a host memory
[Avalon](https://www.intel.com/content/dam/www/programmable/us/en/pdfs/literature/manual/mnl_avalon_spec.pdf)
slave as an FIU protocol. The PIM does not support Avalon MMIO connections
across the PR boundary to the FIU. (Note that the PIM *does* offer
PIM-generated transformations from PR protocols such as CCI-P to Avalon MMIO
masters in the AFU. See the [AFU Interfaces](#afu-interfaces) section below.)
Due to the lack of MMIO support and the requirement that the OPAE MMIO is on
group 0 port 0, Avalon memory slave may not be used as the FIU native protocol
for group 0.

The host channel Avalon protocol has some significant semantic differences
from standard Avalon channels used for simple memories like DDR. These changes
are necessary to maintain high performance across coherent physical buses like
UPI and to enable low-overhead transformations between CCI-P, Avalon and
AXI. Among the most significant differences:

* Avalon reads and writes are split into two separate channels, allowing for
  simultaneous read and write requests. Like CCI-P and AXI, there is no
  defined ordering between read and write completion.

* While both read and write responses are returned in request order, the order
  in which reads and writes are serviced by the FIU is not guaranteed. Like
  CCI-P, writes may commit out of order relative to each other. The same is
  true of reads, even to the same address. The Avalon protocol is extended to
  include encoding for write fences in order to enforce write ordering. The
  write channel includes write responses so AFUs can track write completion.

The Avalon FIU to PR protocol is the same as the Avalon host memory shim
protocol between the PIM and AFUs. Please see the [AFU Avalon](#avalon-memory) host
memory section below for more details.

## AFU Interfaces ##

In the OFS environment the top-level module in the PR region collects the FIU
native interfaces inside a single wrapper interface, named *plat\_ifc*. The
plat\_ifc wrapper is passed to the AFU's top-level module, named
*ofs\_plat\_afu()*. Technically, an AFU could pass the interfaces from
plat\_ifc directly to the AFU. Such an AFU would not be portable across
platforms or even across firmware releases of the same platform. The Platform
Interface Manager (PIM), implemented here, provides an abstraction layer to
map native ports to AFU interface demands.

The primary mechanism for generating AFU interfaces is through modules named
ofs\_plat\_*\<native interface\>*\_as\_*\<AFU interface\>*. So,
*ofs\_plat\_host\_chan\_as\_ccip()* provides a CCI-P AFU interface,
independent of the underlying native interface
type. *ofs\_plat\_host\_chan\_as\_avalon* connects to the same FIU port but
communicates with the AFU over an Avalon channel. These shims are necessarily
specific to the native protocol. The *host\_chan* implicitly refers to the
native protocol without requiring the AFU to know which protocol is in
use. Consequently, the modules are specific to host channel groups. Channel
one's functions are named, e.g., *ofs\_plat\_host\_chan\_g1\_as\_ccip()* --
using the same group naming scheme as ports.

In addition to protocol transformations, the *\_as\_* modules offer both clock
crossing and buffered timing stage insertion. In some cases, the combination
of clock crossing and timing stages is more efficient together than as
separate stages. For example, Avalon timing-stages can employ HyperFlex
registers without checking waitrequest by reserving slots in a clock-crossing
FIFO. AFUs configure clock crossing and timing stage insertion by setting the
ADD_CLOCK_CROSSING and ADD_TIMING_REG_STAGES parameters to *\_as\_* modules.

### CCI-P ###

The CCI-P native protocol and the CCI-P AFU protocol are essentially
identical, documented
[here](https://www.intel.com/content/dam/www/programmable/us/en/pdfs/literature/manual/mnl-ias-ccip.pdf).
CCI-P has evolved over time. Recent platforms may include support for new
fields that encode partial writes to a line. The following SystemVerilog
preprocessor macros are managed by the PIM:

* `CCIP_ENCODING_HAS_BYTE_WR: When defined, the CCI-P structure definitions
  include the fields required for describing byte ranges within a write
  request. Note: the presence of the data structures does not guarantee that
  the platform actually supports byte ranges. The macro only indicates that
  the CCI-P data structure version is recent enough to include the
  encoding. The PIM indicates platform support for partial line writes with
  the flag ccip_cfg_pkg::BYTE_EN_SUPPORTED.

* `CCIP_ENCODING_HAS_RDLSPEC: Indicates that the CCI-P encoding has support
  for speculative reads. The [MPF Basic Building
  Blocks](https://github.com/OPAE/intel-fpga-bbb/tree/master/BBB_cci_mpf) are
  currently the only RTL using speculative reads. MPF permits speculation on
  virtual to physical address translation, optionally returning failed
  speculation instead of an error on failed address translation.

The PIM records many platform-specific properties in ccip_cfg_pkg. See the
[ccip_cfg_pkg.sv](native_ccip/ccip_GROUP_cfg_pkg.sv)
source for details.


#### Instantiating an AFU CCI-P Interface ####

TBD

### Avalon Memory ###

There are two categories of Avalon memory AFU interfaces: a slave for host
memory implemented in the FIU and a master for MMIO space provided by the
AFU. An MMIO master must be provided by the AFU for group 0 port 0 (the OPAE
MMIO space in which AFUs identify themselves). MMIO is optional on other
ports.

#### Host Memory Slave ####

The host memory slave interface is defined in
[ofs_plat_avalon_mem_rdwr_if.sv](../base_ifcs/avalon/ofs_plat_avalon_mem_rdwr_if.sv).
This interface has some unusual syntax and semantics in order to achieve
acceptable host memory performance:

* There are separate read and write buses. The buses share only clk and
  reset. A standard Avalon port with a shared address bus would have to run at
  unreasonably high frequencies to reach available host memory
  bandwidth. Splitting the bus also keeps the Avalon interface semantics
  similar to both CCI-P and AXI, which also define split buses. There is no
  defined order between reads and writes.

* The write bus implements the standard Avalon *writeresponsevalid*
  signal. Write responses indicate commit of a write to host memory. Reads and
  writes to the port requested after the commit signal are guaranteed to
  follow the committed write. Note that *commit* is not a guarantee of
  that the value is visible through some other port. Cross-port
  synchronization is platform-dependent.

* Write-write ordering is not guaranteed, even to the same address. This
  reordering allows the FIU to improve performance in cached protocols, where
  cache hits can be serviced while other misses wait for ownership. Despite
  potential reordering within the FIU, write responses are returned in
  order. The Avalon bus has no tags to match requests with responses, making
  ordered responses a necessity.

  There are two mechanisms implemented in the write bus for managing order. As
  noted above, an AFU could wait for *writeresponsevalid* before issuing a new
  ordered write. Alternatively, a non-standard *wr\_request* field is added to
  the interface. Setting wr\_request indicates a memory fence. All writes
  preceding a fence will commit before any writes following the fence. When
  wr\_request is set the wr\_address field must be 0. Non-zero addresses are
  reserved for future use.

* Read-read ordering is also not guaranteed inside the FIU. A read may return
  a stale value relative to another read. Like write responses, read responses
  are sorted before they are returned to the AFU due to Avalon's lack of
  meta-data for correlating read requests with responses.

  The interface defines a non-standard *rd\_request* field in order to match
  *wr\_request*. rd\_request is currently reserved and must be set to 0.

* Both the wr\_request and the rd\_request fields may be safely routed through
  standard Avalon networks by merging them into their corresponding address
  fields. Make the address field one bit wider and pass {wr\_request,
  wr\_address} through the standard address field.

* Both wr\_byteenable and rd\_byteenable are defined. When used, only
  contiguous regions may be specified. Not all platforms support byte
  enable. When available, the TBD PIM flag is set.

#### MMIO Memory Master ####

The AFU Avalon MMIO master interface is a standard Avalon bus with an address
shared by reads and writes. It is defined in
[ofs_plat_avalon_mem_if.sv](../base_ifcs/avalon/ofs_plat_avalon_mem_if.sv).
OPAE assumes that MMIO requests are committed in request order.

#### Instantiating an AFU Avalon Memory Interface ####

TBD
