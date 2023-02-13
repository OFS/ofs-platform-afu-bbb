# PIM Core Concepts

The Platform Interface Manager (PIM) is a transformation layer between an AFU and raw FIM device interfaces. It aims to provide consistent AFU-side interfaces and semantics, making AFUs portable across OFS releases. The PIM is the composition of:

1. Standard AFU-side SystemVerilog interfaces, both AXI and Avalon memory mapped and streaming.
2. PIM-provided modules that transform FIM interfaces to PIM interfaces. Transformations may be simple, such as mapping a FIM AXI-MM interface to the PIM's AXI-MM. Transformations may also be complex, such as mapping a PCIe TLP stream to AXI-MM, adding a clock crossing and sorting read responses.
3. A top-level module and interface bundle with consistent naming across all platforms, promoting AFU portability.
4. A collection of Python scripts that generate a platform-specific instance of a PIM that implements #2 and #3.

## Terminology

* **Base interfaces**: Standard AXI and Avalon interfaces, both memory mapped and streaming, that are the bus definitions between AFUs and the PIM.
* **Native interfaces**: Platform specific, device interfaces that are the bus definitions between the PIM and the FIM.
* **Host channel**: Any device interface that connects to a CPU's memory or exposes memory mapped CSRs to a CPU. PCIe and CXL are both examples of host channels.
* **Local memory**: Any on-board memory that is private to the FPGA. On-board DDR RAM and HBM are both examples of local memory.
* **Shim**: A module that both consumes and produces a bus and applies some transformation.

## PIM Base SystemVerilog Interfaces

On the AFU side of its shims, all PIM modules share common base AXI and Avalon interfaces. The same interfaces are used for host channels and local memory. These base interfaces rarely change. All base interfaces are defined under [plat_if_develop/ofs_plat_if/src/rtl/base_ifcs](https://github.com/OFS/ofs-platform-afu-bbb/tree/master/plat_if_develop/ofs_plat_if/src/rtl/base_ifcs).

AXI memory mapped \([ofs_plat_axi_mem_if.sv](https://github.com/OFS/ofs-platform-afu-bbb/blob/master/plat_if_develop/ofs_plat_if/src/rtl/base_ifcs/axi/ofs_plat_axi_mem_if.sv)\) and AXI Lite \([ofs_plat_axi_mem_lite_if.sv](https://github.com/OFS/ofs-platform-afu-bbb/blob/master/plat_if_develop/ofs_plat_if/src/rtl/base_ifcs/axi/ofs_plat_axi_mem_lite_if.sv)\) interfaces are both defined and contain the standard five channels. The PIM wraps each channel's payload in a packed struct in order to simplify copying the payload, eliminating the common bug of missing a field when copying data. Structs also make it possible to add fields without breaking compatibility. For example, the AXI-MM write channel definition is:

```SystemVerilog
    typedef struct packed {
        t_data data;
        t_byte_mask strb;
        logic last;
        t_user user;
    } t_axi_mem_w;

    t_axi_mem_w w;
    logic wvalid;
    logic wready;
```

Two classes of Avalon channels are defined. [ofs_plat_avalon_mem_if.sv](https://github.com/OFS/ofs-platform-afu-bbb/blob/master/plat_if_develop/ofs_plat_if/src/rtl/base_ifcs/avalon/ofs_plat_avalon_mem_if.sv) is the traditional Avalon-MM interface with an address bus that is shared by reads and writes. [ofs_plat_avalon_mem_rdwr_if.sv](https://github.com/OFS/ofs-platform-afu-bbb/blob/master/plat_if_develop/ofs_plat_if/src/rtl/base_ifcs/avalon/ofs_plat_avalon_mem_rdwr_if.sv) separates reads and writes into independent channels. The split-bus variant offers higher bandwidth and easier mapping to native interfaces that are symmetrical, such as PCIe.

AXI streaming interfaces are also defined \([ofs_plat_axi_stream_if.sv](https://github.com/OFS/ofs-platform-afu-bbb/blob/master/plat_if_develop/ofs_plat_if/src/rtl/base_ifcs/axi/ofs_plat_axi_stream_if.sv)\). Unlike the memory mapped interfaces, a streaming interface is merely a container around a bus. AXI-S defines only the ready/enable protocol.

Most AFUs that rely on the PIM will define instances of base interfaces and connect them to PIM-provided shims.

## Shims

The PIM's naming convention for shims is the key to portability. The shim that maps a host channel to AXI-MM interfaces is always called ofs_plat_host_chan_as_axi_mem_with_mmio\(\). This is true for any underlying device type or platform. The same name is available, independent of platform-specific PCIe TLP encoding. Shims take standard parameters that control their behavior, such as ADD_CLOCK_CROSSING and SORT_READ_RESPONSES. Internally, shim implementations are platform specific. If read responses are already guaranteed to be ordered, SORT_READ_RESPONSES has no effect. If read responses may be out of order from the FIM, the shim will add a reorder buffer. Consequently, an AFU may set parameters as needed and expect that the underlying implementation will be optimized for the target platform.

The PIM typically provides both AXI and Avalon mappings for the same native interface. For example, all platforms with local memory offer both ofs_plat_local_mem_as_avalon_mem\(\) and ofs_plat_local_mem_as_axi_mem\(\) as shims for native DDR RAM banks, whether the native memory interface is AXI or Avalon. The implementations of the two modules will be different for native AXI vs. Avalon, but the features and naming conventions visible to an AFU remain consistent. An AFU may specify an Avalon-MM interface for local memory on any platform, whether the native memory interface is Avalon-MM or AXI-MM.

Example AFUs that demonstrate these concepts, starting with a basic hello world, are available in the [example AFU tutorial](https://github.com/OFS/examples-afu/tree/main/tutorial).

## Top-level module: ofs_plat_afu\(\)

After shims, the PIM-provided ofs_plat_afu\(\) is the second key to portability. The OFS compilation environment can be configured to load a user-provided ofs_plat_afu\(\) module. All AFU logic is then instantiated under ofs_plat_afu\(\). The PIM wraps all FIM devices in a single container, which is passed to ofs_plat_afu\(\) as a port named *plat_ifc*. The contents of plat_ifc are platform-specific, but a naming convention keeps logic consistent across devices. For example, host channels inside plat_ifc will always be wrapped as a vector of interfaces named *plat_ifc.host_chan.ports\[\]*.

Shims can be used with or without ofs_plat_afu\(\). Examples of design patterns with PIM-provided shims with and without ofs_plat_afu\(\) are covered in the [example AFU tutorial](https://github.com/OFS/examples-afu/tree/main/tutorial).

## Composing a PIM Instance

The PIM is implemented as a collection of shim templates and Python scripts. Each OFS FIM provides a configuration file that describes the board's interface. PIM Python scripts select the appropriate [shims from the set of supported native interfaces](https://github.com/OFS/ofs-platform-afu-bbb/tree/master/plat_if_develop/ofs_plat_if/src/rtl/ifc_classes) to implement a board-specific PIM instance. For example, when a board's native DDR RAM interface is AXI-MM, the PIM scripts will instantiate ofs_plat_local_mem_as_avalon_mem\(\) and ofs_plat_local_mem_as_axi_mem\(\) from the [local memory native AXI](https://github.com/OFS/ofs-platform-afu-bbb/tree/master/plat_if_develop/ofs_plat_if/src/rtl/ifc_classes/local_mem/native_axi) variant.

The plat_ifc instance passed through ofs_plat_afu\(\) is also constructed by Python scripts when the FIM is configured. The scripts are responsible for adding board-specific interfaces to plat_ifc.

PIM composition is described in the section aimed at [board vendors](PIM_board_vendors.md).

## Further Reading

For AFU developers, [Connecting an AFU to a Platform](PIM_AFU_interface.md) describes the top-level ofs_plat_afu\(\) module and shims in more detail. A [tutorial with synthesizable examples](https://github.com/OFS/examples-afu/tree/main/tutorial) and inline comments demonstrates building AFUs with the PIM.

For board developers, [Board Vendors: Configuring a Release](PIM_board_vendors.md) covers defining a PIM instance for the native interfaces on a new board, along with methods for supporting new classes of native devices.

Detailed documentation is available on instantiating and formatting requests on [PIM memory mapped host channels](PIM_ifc_host_channel.md).
