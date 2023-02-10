# AFU Developers: Connecting an AFU to a Platform #

The Platform Interface Manager (PIM) is the interface between an accelerator (an AFU) and the platform (the FIM). AFU developers rely on two of the core components covered in [PIM Core Concepts](PIM_core_concepts.md):

1. Shims for transforming standardized AFU-side interfaces to platform-specific FIM interfaces.
2. A fixed top-level module name and SystemVerilog wrapper around FIM interfaces.

These two components are actually separable, though full cross-platform portability depends on using both together. Here, we will describe the PIM under the assumption that both are used.

PIM-provided shims include protocol transformations, clock crossing, response sorting, and buffering. Board developers provide platform-specific PIM instances for use by AFU developers. Ideally, a PIM instance exports standard AFU-side interfaces despite internal FIM differences. A board with PCIe TLPs encapsulated in an AXI stream and a board with PCIe wrapped in Intel's CCI-P protocol can both provide the same PIM module names to map PCIe traffic to AXI and Avalon memory interfaces. The implementation of the shims will be radically different, but both are compatible black boxes from the AFU's perspective. With consistent interfaces it becomes possible to write cross-platform AFUs, despite what may be significant underlying FIM changes. Of course an AFU that depends on local memory will not synthesize on a board with no local memory. The AFU may, however, adapt to variations in topology of local memory.

The top level of an AFU is always the same on all PIM-based platforms:

```SystemVerilog
`include "ofs_plat_if.vh"

module ofs_plat_afu
   (
    // All platform wires, wrapped in one interface.
    ofs_plat_if plat_ifc
    );

    . . .

endmodule
```

The *ofs\_plat\_if.vh* include file imports all preprocessor macros and types in the PIM.

It is the responsibility of FIM developers to construct a platform-specific PIM as part of generating a release for AFU-development. The topology of a release and PIM-construction tools are described in *[Board Vendors: Configuring a Release](PIM_board_vendors.md)*. AFU developers set the environment variable *OPAE\_PLATFORM\_ROOT* to the root of a release tree. PIM sources are found in *\${OPAE\_PLATFORM\_ROOT}/hw/lib/build/platform/ofs\_plat\_if*.

The SystemVerilog interface *ofs\_plat\_if* wraps all connections to the FIM's devices. The contents of ofs\_plat\_if may vary from device to device. Portability is maintained by conforming to standard naming conventions. ofs\_plat\_if is, itself, a collection of interface wrappers to groups of devices. The wrapper is constructed from the .ini file and scripts described in the [board vendors section](PIM_board_vendors.md). The sample below is the wrapper for the OFS-based n6001 board, with AXI stream ports wrapping PCIe TLP, four AXI-MM local memory banks, and HSSI ports. The extra *other* extension interface is merely an example, described in the [board vendors section](PIM_board_vendors.md), and can be ignored here. The interface is nearly identical to the versions from other platforms, despite significant underlying protocol differences, because the actual channel types are defined inside sub-interfaces declared in ofs\_plat\_if.

```SystemVerilog
interface ofs_plat_if
  #(
    parameter ENABLE_LOG = 0
    );

    // Required: platform top-level clocks
    wire t_ofs_plat_std_clocks clocks;

    // Required: active low soft reset (clocked by pClk). This reset
    // is identical to clocks.pClk.reset_n.
    logic softReset_n;
    // Required: AFU power state (clocked by pClk)
    t_ofs_plat_power_state pwrState;

    // Each sub-interface is a wrapper around a single vector of ports or banks.
    // Each port or bank in a vector must be the same configuration. Namely,
    // multiple banks within a local memory interface must all have the same
    // width and depth. If a platform has more than one configuration of a
    // class, e.g. both DDR and static RAM, those should be instantiated here
    // as separate interfaces.

    ofs_plat_host_chan_fiu_if
      #(
        .ENABLE_LOG(ENABLE_LOG)
        )
        host_chan();

    ofs_plat_local_mem_fiu_if
      #(
        .ENABLE_LOG(ENABLE_LOG)
        )
        local_mem();

    ofs_plat_hssi_fiu_if
      #(
        .ENABLE_LOG(ENABLE_LOG)
        )
        hssi();

    ofs_plat_other_fiu_if
      #(
        .ENABLE_LOG(ENABLE_LOG)
        )
        other();

endinterface // ofs_plat_if
```

A standard type, defined in [ofs\_plat\_clocks.vh](../src/rtl/base_ifcs/clocks/ofs_plat_clocks.vh), wraps the usual pClk, pClkDiv2, pClkDiv4, uClk\_user and uClk\_userDiv2 that are exported by the FIM. Corresponding active low resets are also provided, all derived from the base soft reset and crossed into each clock domain. The user clock is thus accessible as *plat\_ifc.clocks.uClk\_usr.clk* on any conforming platform and the corresponding active low reset as *plat\_ifc.clocks.uClk\_usr.reset\_n*. Individual platform vendors may also add non-standard clocks to the structure, though these will not be portable.

One more interface layer wraps groups of ports that all share the same properties. Standard names are used for portability:

* **host\_chan** — Host channels are connections to the host that support either DMA to host memory or define CSR spaces for host interaction. PCIe TLP streams and Intel's CCI-P memory mapped interface are both types of host channels.
* **local\_mem** — Local memory is off-chip memory connected to an FPGA but not visible to the host as system memory.
* **hssi** — High-speed serial interfaces such as Ethernet.

At the top level of the interface hierarchy the syntax remains platform-independent. Internally, however, these interfaces are platform-specific. On the n6001 board the host channel uses AXI streams and is defined as:

```SystemVerilog
interface ofs_plat_host_chan_fiu_if
  #(
    parameter ENABLE_LOG = 0,
    parameter NUM_PORTS = `OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS
    );

    ofs_plat_host_chan_axis_pcie_tlp_if
      #(
        .LOG_CLASS(ENABLE_LOG ? ofs_plat_log_pkg::HOST_CHAN : ofs_plat_log_pkg::NONE)
        )
        ports[NUM_PORTS]();

endinterface // ofs_plat_host_chan_fiu_if
```

Finally, we have reached the point at which the AXI stream ports exposed by the FIM are defined and passed to the AFU. They are visible as elements in the *plat\_ifc.host\_chan.ports* array. Local memory has similar syntax:

```SystemVerilog
interface ofs_plat_local_mem_fiu_if
  #(
    parameter ENABLE_LOG = 0,
    parameter NUM_BANKS = `OFS_PLAT_PARAM_LOCAL_MEM_NUM_BANKS,
    parameter WAIT_REQUEST_ALLOWANCE = 0
    );

    ofs_plat_axi_mem_if
      #(
        .LOG_CLASS(ENABLE_LOG ? ofs_plat_log_pkg::LOCAL_MEM : ofs_plat_log_pkg::NONE),

        .WAIT_REQUEST_ALLOWANCE(WAIT_REQUEST_ALLOWANCE),
        `LOCAL_MEM_AXI_MEM_PARAMS_FULL_BUS_DEFAULT
        )
        banks[NUM_BANKS]();

endinterface // ofs_plat_local_mem_fiu_if
```

and is visible as *plat\_ifc.local\_mem.banks[0]* through  *plat\_ifc.local\_mem.banks[3]* on this 4-bank platform.

The ENABLE\_LOG and LOG\_CLASS parameters control simulation-time logging of traffic for debugging. OFS PIM interfaces typically are able to log requests and responses flowing through any instance of an interface. In ASE-based simulation, LOG\_ENABLE is turned on in plat\_ifc. HOST\_CHAN traffic is logged to work/log\_ofs\_plat\_host\_chan.tsv and local memory to work/log\_ofs\_plat\_local\_mem.tsv. OFS interfaces are also self-checking in simulation. For example, a simulation-time error will fire if an Avalon memory interface has *write* asserted but a bit in *address* is uninitialized.

The preprocessor macros are included by *ofs\_plat\_if.vh* and are defined in *\${OPAE\_PLATFORM\_ROOT}/hw/lib/build/platform/ofs\_plat\_if/rtl/ofs\_plat\_if\_top\_config.vh*. They are derived from the .ini file used by FIM architects to build the PIM, as described in *[Board Vendors: Configuring a Release](PIM_board_vendors.md)*. Any property defined as a [default](PIM_board_vendors.md#defaults) is guaranteed to have a corresponding preprocessor macro. An AFU can test whether a particular board has local memory by testing whether the macro *OFS\_PLAT\_PARAM\_LOCAL\_MEM\_NUM\_BANKS* is defined.

While an AFU could connect directly to a port in *plat\_ifc.host\_chan.ports[0]*, this is generally inadvisable as it is not portable. The PIM provides wrapper shims with standard names that act as abstraction layers. In the simplest case, where an AFU requests *plat\_ifc.host\_chan.ports[0]* with a protocol identical to the native implementation of the port, the shim is just wires and consumes no area. If the AFU requests a different protocol from the native implementation, such as Avalon instead of AXI, the PIM will instantiate a protocol translation layer. An AFU will compile as long as the FIM architect has provided the module offering support for the AFU's target protocol, independent of a port's underlying native protocol.

On a single platform, either of the following becomes possible:

```SystemVerilog
    // ====================================================================
    //
    //  Get an AXI host channel connection from the platform.
    //
    // ====================================================================

    // Host memory AFU source
    ofs_plat_axi_mem_if
      #(
        `HOST_CHAN_AXI_MEM_PARAMS,
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        host_mem_to_afu();

    // 64 bit read/write MMIO AFU sink
    ofs_plat_axi_mem_lite_if
      #(
        `HOST_CHAN_AXI_MMIO_PARAMS(64),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio64_to_afu();

    // Map FIU interface to AXI host memory and MMIO
    ofs_plat_host_chan_as_axi_mem_with_mmio
      #(
        .ADD_TIMING_REG_STAGES(2)
        )
      primary_axi
       (
        .to_fiu(plat_ifc.host_chan.ports[0]),
        .host_mem_to_afu,
        .mmio_to_afu(mmio64_to_afu),

        .afu_clk(),
        .afu_reset_n()
        );
```

or:

```SystemVerilog
    // ====================================================================
    //
    //  Get a CCI-P port from the platform.
    //
    // ====================================================================

    // Instance of a CCI-P interface. The interface wraps usual CCI-P
    // sRx and sTx structs as well as the associated clock and reset.
    ofs_plat_host_ccip_if ccip_to_afu();

    // Use the platform-provided module to map the primary host interface
    // to CCI-P. The "primary" interface is the port that includes the
    // main OPAE-managed MMIO connection.
    ofs_plat_host_chan_as_ccip
      primary_ccip
       (
        .to_fiu(plat_ifc.host_chan.ports[0]),
        .to_afu(ccip_to_afu)
        );
```

As long as a FIM developer provides both *ofs\_plat\_host\_chan\_as\_axi\_mem\_with\_mmio()* and *ofs\_plat\_host\_chan\_as\_ccip()*, these samples will compile on any platform.

### Clock Crossing, Buffering and Reordering ###

In addition to protocol transformations, the PIM is capable of instantiating some common bus transformations that are often required by AFUs. Most PIM top-level shims allow AFUs to request clock domain crossings by setting ADD\_CLOCK\_CROSSING. Protocols that naturally respond out of order may have options to instantiate reorder buffers. Implementing these in the PIM can be quite efficient. Consider the case of a native PCIe TLP stream being exported as an Avalon memory interface. The implementation already requires buffering on the DMA response channels from the PCIe interface toward the AFU master in order to handle flow control. Adding clock crossing and even a reorder buffer that sorts responses consumes very little additional area. The tags used for reordering can be the same tags already required by PCIe TLPs. Implementing clock crossing or reordering elsewhere in the design would require duplication of the large response buffer. When an interface already returns ordered responses, the PIM ignores SORT\_READ\_RESPONSES and does not waste area on an unnecessary reorder buffer.

Every major PIM interface defines a wire named *clk* and an active low reset port, *reset_n*, in the *clk* domain. PIM-instantiated clock crossing updates these wires.

The AFU with an AXI-MM host channel (host\_mem\_to\_afu) described above can connect to local memory, mapping it to the host channel's clock simply by setting ADD\_CLOCK\_CROSSING when connecting to local memory:

```SystemVerilog
    ofs_plat_local_mem_as_axi_mem
      #(
        .ADD_CLOCK_CROSSING(1)
        )
      local_mem
       (
        .to_fiu(plat_ifc.local_mem.banks[0]),
        .to_afu(local_mem_to_afu[0])

        .afu_clk(host_mem_to_afu.clk),
        .afu_reset_n(host_mem_to_afu.reset_n)
        );
```

Now, *local\_mem\_to\_afu[0]* and *host\_mem\_to\_afu* are operating in the same clock domain. Similarly, the CCI-P port from the host channel example above can both be sorted and moved to uClk_user:

```SystemVerilog
    ofs_plat_host_ccip_if ccip_to_afu();

    ofs_plat_host_chan_as_ccip
      #(
        .ADD_CLOCK_CROSSING(1),
        .SORT_READ_RESPONSES(1)
        )
      primary_ccip
       (
        .to_fiu(plat_ifc.host_chan.ports[0]),
        .to_afu(ccip_to_afu),

        .afu_clk(plat_ifc.clocks.uClk_usr.clk),
        .afu_reset_n(plat_ifc.clocks.uClk_usr.reset_n)
        );
```

Typically, extra register stages can also be added for timing by setting ADD\_TIMING\_REG\_STAGES(num\_stages).

### Burst Count Gearboxes ###

As another abstraction layer, the PIM permits mismatched maximum burst sizes of Avalon and AXI interfaces between an AFU and the native port. When an AFU requests bursts larger than those supported by the native device interface, the PIM adds a gearbox to map large bursts into smaller ones that fit. Burst mapping may also be added in order to satisfy alignment requirements, emitting smaller bursts until natural alignment is achieved. The gearbox suppresses extra write responses for requests that are broken up so that the AFU will see responses only when the original burst completes.

Maximum burst sizes are derived from the AFU-defined SystemVerilog interface instances. The example above that connected an AXI channel to the primary host_chan with a maximum burst size of 64 can, instead, set the maximum burst size to 128 simply by changing the declaration of the *host\_mem\_to\_afu* interface:

```SystemVerilog
    // Host memory AFU master
    ofs_plat_axi_mem_if
      #(
        `HOST_CHAN_AXI_MEM_PARAMS,
        .BURST_CNT_WIDTH(7)
        )
        host_mem_to_afu();
```

### Tie-Offs ###

One impediment to portability is proper tie-offs of unused devices. An AFU written today can not anticipate new devices that may be added to future platforms. The PIM solves this by inverting the normal tie-off process: an AFU declares the interfaces to which it has connected. The PIM ties off all other ports.

Tie-offs are passed to the PIM as bit masks in parameters. The mask makes it possible to indicate, for example, that a single local memory bank is being driven. If a future platform adds an additional local memory bank, the PIM will tie it off while maintaining the AFU's connection to bank 0. There is no harm to setting mask bits that don't correspond to devices on a particular board. An AFU that will connect to however many memory banks are offered can safely set the mask to -1, indicating all banks have connections.

Tie-off parameters are all of the form: *\<interface class\>\_IN\_USE\_MASK()*. Every AFU is expected to instantiate the tie-off module:

```SystemVerilog
    // ====================================================================
    //
    //  Tie off unused ports.
    //
    // ====================================================================

    ofs_plat_if_tie_off_unused
      #(
        .HOST_CHAN_IN_USE_MASK(1),
        // All banks are used
        .LOCAL_MEM_IN_USE_MASK(-1)
        )
        tie_off(plat_ifc);
```

### Interface Groups ###

The PIM supports multiple instances of the same interface class. All interfaces in a vector of banks must be identical. A board with 4 banks of DDR4 memory and 2 banks of SRAM requires two instances of a local\_mem, each with different parameters. The general naming of an interface group is *\<interface class\>\_G\<group number\>*, e.g. *LOCAL\_MEM\_G1*. All the examples so far with a single group of each class are merely a special case, *\_G0* is always removed, so *LOCAL\_MEM\_G0* is simply *LOCAL\_MEM*.

Since each group of interfaces may have different configuration parameters and may even be implemented in different native protocols, all modules and macros are named with the group number. An AFU connects to group 1 of local memory with group 1 names:

```SystemVerilog
    ofs_plat_avalon_mem_if
      #(
        `LOCAL_MEM_G1_AVALON_MEM_PARAMS,
        .BURST_CNT_WIDTH(6)
        )
      local_mem_g1_to_afu[local_mem_g1_cfg_pkg::LOCAL_MEM_NUM_BANKS]();

    // Handle the clock crossing in the OFS module.
    ofs_plat_local_mem_g1_as_avalon_mem
      #(
        .ADD_CLOCK_CROSSING(1)
        )
      local_mem_g1
       (
        .to_fiu(plat_ifc.local_mem_g1.banks[0]),
        .to_afu(local_mem_g1_to_afu[0])

        .afu_clk(host_mem_to_afu.clk),
        .afu_reset_n(host_mem_to_afu.reset_n)
        );
```

Each group must be named separately when managing tie-offs:

```SystemVerilog
    ofs_plat_if_tie_off_unused
      #(
        .HOST_CHAN_IN_USE_MASK(1),
        .LOCAL_MEM_IN_USE_MASK(-1),
        // Bank 0 of group 1 used
        .LOCAL_MEM_G1_IN_USE_MASK(1)
        )
        tie_off(plat_ifc);
```

## Tutorial ##

A hands-on introduction to PIM-based AFUs is available in the [OFS example AFUs repository](https://github.com/OFS/examples-afu/tree/main/tutorial). It covers simulation and synthesis of AFUs and provides simple examples that map host channels and local memory banks. Using PIM-provided shims without the PIM's top-level ofs\_plat\_afu module is also covered.