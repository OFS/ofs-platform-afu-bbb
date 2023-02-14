# Local Memory Mapping

PIM shims that map from native local memory device interfaces to the PIM's AXI-MM and Avalon-MM interfaces are relatively simple. Local memory native protocols, whether DDR RAM or HBM, are already memory mapped interfaces. The PIM shims may include clock crossing, burst size mapping and protocol transformation between AXI-MM and Avalon-MM.

Both AFU-side AXI-MM and Avalon-MM shims are offered on all platforms, independent of the native interface.

The AFU-side local memory interfaces used by the PIM are identical to the memory mapped interfaces used for host channels.

When using the PIM's ofs_plat_afu\(\) top-level module, native local memory is organized in groups and banks. Within a group, all banks have the same address and data widths. A platform with only a single group of banks has native interfaces named plat_ifc.local_mem.banks\[\], with local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS in the banks vector. As described in the [board vendors section](PIM_board_vendors.md), a second group of memory would be plat_ifc.local_mem_g1.banks\[\], with local_mem_g1_cfg_pkg::LOCAL_MEM_NUM_BANKS. The [local_mem_params](../../../plat_if_tests/local_mem_params/hw/rtl/axi/ofs_plat_afu.sv) PIM test detects multiple groups and banks of memory using PIM-provided naming.

## AXI-MM Local Memory

The PIM's AXI interfaces define the payload for each AXI bus inside a struct so that all fields can be copied in a single statement. This simplifies code inside the PIM and reduces opportunities for bugs. See the discussion in [PIM core concepts](PIM_core_concepts.md#pim-base-systemverilog-interfaces). Documentation of both AXI-MM and AXI-Lite below include links to the interface definitions and structs.

### Local memory AXI-MM

Define the host memory AXI-MM interface. Here, we instantiate a vector of interfaces -- one per bank:

```SystemVerilog
    ofs_plat_axi_mem_if
      #(
        `LOCAL_MEM_AXI_MEM_PARAMS_DEFAULT,
        .LOG_CLASS(ofs_plat_log_pkg::LOCAL_MEM)
        )
      local_mem_to_afu[local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS]();
```

The \`LOCAL_MEM_AXI_MEM_PARAMS_DEFAULT macro sets address and data widths to match the native interface, along with burst count and ID field sizes. AFUs may set the burst count field larger than the native interface. The PIM will convert large bursts into device-sized bursts. To change the burst count width, use the shorter \`LOCAL_MEM_AXI_MEM_PARAMS and define the extra ofs_plat_axi_mem_if parameters as needed. Both macros are defined in [ofs_plat_local_mem_axi_mem.vh](../src/rtl/ifc_classes/local_mem/afu_ifcs/ofs_plat_local_mem_GROUP_axi_mem.vh).

### Local memory shim

Instantiate the shim that maps a local memory bank to the AXI-MM interface. When mapping multiple banks, this is typically in a generate block loop:

```SystemVerilog
    generate
        for (genvar b = 0; b < local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS; b = b + 1)
        begin : mb
            ofs_plat_local_mem_as_axi_mem
              #(
                // Add a clock crossing from bank-specific clock.
                .ADD_CLOCK_CROSSING(1)
                )
              shim
               (
                .to_fiu(plat_ifc.local_mem.banks[b]),
                .to_afu(local_mem_to_afu[b]),

                // Map to the same clock as the AFU's host channel
                // interface. Whatever clock is chosen above in primary_hc
                // will be used here.
                .afu_clk(mmio64_to_afu.clk),
                .afu_reset_n(mmio64_to_afu.reset_n)
                );
        end
    endgenerate
```

All host channel mapping shims have a common set of optional parameters:

* When non-zero, ADD_CLOCK_CROSSING includes a clock crossing from the native interface's default clock to a clock passed into the afu_clk/afu_reset_n pair of ports. In the example above, local_mem_to_afu\[\] is clocked by mmio64_to_afu.clk.
* SORT_READ_RESPONSES, when set, guarantees that read responses will arrive in request order. Most memory is already ordered, in which case SORT_READ_RESPONSES defaults to 1. The PIM adds a reorder buffer only when the native interface might return responses out of order.
* SORT_WRITE_RESPONSES is the equivalent setting for write requests and responses.
* ADD_TIMING_REG_STAGES adds the specified number of register stages at the border to the native interface.

#### Tags and ordering

AXI-MM permits duplicate tags on read and write requests. In the rare case that memory responses are unordered and SORT_READ_RESPONSES or SORT_WRITE_RESPONSES is not set, tags are passed directly to the native device. In that case, AFU developers are expected to understand the tag semantics of the native device.

#### Bursts

Only incrementing address mode is supported. Addresses must be aligned to the bus width. Lower address bits that index bytes within the data bus are ignored.

Burst length is limited only by the width of the burst count field, which is set by the BURST_CNT_WIDTH parameter to the [AXI-MM interface](../src/rtl/base_ifcs/axi/ofs_plat_axi_mem_if.sv). Bursts may cross any address boundary, including 4KB pages. The PIM will break apart large bursts as needed, depending on both alignment and size restrictions of the native interface.

#### Masked writes

AXI-MM defines strobe bits on the write data bus that mask write data, reducing the range of a write. The PIM imposes the following restrictions on the use of masked write data:

* Strobe bits may be zero only at the beginning or the end of a data range. No zero bits are permitted between ones.
* Bursts longer than one beat with masks are supported as long as any zero strobe bits are at the beginning of the first beat and/or the end of the last.

## Avalon-MM Local Memory

The PIM local memory Avalon-MM mapping using the PIM's normal [ofs_plat_avalon_mem_if](../src/rtl/base_ifcs/avalon/ofs_plat_avalon_mem_if.sv) with a shared address bus. The split-bus used for the host memory interface is unnecessary since RAM uses a shared bus.

### Local memory Avalon-MM

Define the host memory Avalon-MM interface. Here, we instantiate a vector of interfaces -- one per bank:

```SystemVerilog
    ofs_plat_avalon_mem_if
      #(
        `LOCAL_MEM_AVALON_MEM_PARAMS_DEFAULT,
        .LOG_CLASS(ofs_plat_log_pkg::LOCAL_MEM)
        )
      local_mem_to_afu[local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS]();
```

The \`LOCAL_MEM_AVALON_MEM_PARAMS_DEFAULT macro sets address and data widths to match the native interface, along with the burst count width. AFUs may set the burst count field larger than the native interface. The PIM will convert large bursts into device-sized bursts. To change the burst count width, use the shorter \`LOCAL_MEM_AVALON_MEM_PARAMS and define the extra ofs_plat_avalon_mem_if parameters as needed. Both macros are defined in [ofs_plat_local_mem_avalon_mem.vh](../src/rtl/ifc_classes/local_mem/afu_ifcs/ofs_plat_local_mem_GROUP_avalon_mem.vh).

### Local memory shim

Instantiate the shim that maps a local memory bank to the Avalon-MM interface. When mapping multiple banks, this is typically in a generate block loop:

```SystemVerilog
    generate
        for (genvar b = 0; b < local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS; b = b + 1)
        begin : mb
            ofs_plat_local_mem_as_avalon_mem
              #(
                // Add a clock crossing from bank-specific clock.
                .ADD_CLOCK_CROSSING(1)
                )
              shim
               (
                .to_fiu(plat_ifc.local_mem.banks[b]),
                .to_afu(local_mem_to_afu[b]),

                // Map to the same clock as the AFU's host channel
                // interface. Whatever clock is chosen above in primary_hc
                // will be used here.
                .afu_clk(mmio64_to_afu.clk),
                .afu_reset_n(mmio64_to_afu.reset_n)
                );
        end
    endgenerate
```

All host channel mapping shims have a common set of optional parameters:

* When non-zero, ADD_CLOCK_CROSSING includes a clock crossing from the native interface's default clock to a clock passed into the afu_clk/afu_reset_n pair of ports. In the example above, local_mem_to_afu\[\] is clocked by mmio64_to_afu.clk.
* ADD_TIMING_REG_STAGES adds the specified number of register stages at the border to the native interface.

Avalon-MM interfaces are ordered. Read responses are returned in request order.

#### Bursts

Burst length is limited only by the width of the burst count field, which is set by the BURST_CNT_WIDTH parameter to the [Avalon-MM interface](../src/rtl/base_ifcs/avalon/ofs_plat_avalon_mem_if.sv). Bursts may cross any address boundary, including 4KB pages. The PIM will break apart large bursts as needed, depending on both alignment and size restrictions of the native interface.

#### Masked writes

Avalon-MM defines byte enable bits on the write data bus that mask write data, reducing the range of a write. The PIM imposes the following restrictions on the use of masked write data:

* Byte enable bits may be zero only at the beginning or the end of a data range. No zero bits are permitted between ones.
* Bursts longer than one beat with masks are supported as long as any zero byte enable bits are at the beginning of the first beat and/or the end of the last.
