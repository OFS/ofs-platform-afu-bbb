// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Export a CCI-P native host_chan interface to an AFU as AXI interfaces.
// There are three AXI interfaces: host memory source, MMIO (FPGA memory
// sink) and write-only MMIO sink. The write-only variant can be useful
// for 512 bit MMIO. CCI-P supports wide MMIO write but not read.
//

`include "ofs_plat_if.vh"

//
// There are three public variants:
//  - ofs_plat_host_chan_@group@_as_axi_mem - host memory only.
//  - ofs_plat_host_chan_@group@_as_axi_mem_with_mmio - host memory and
//    a single read/write MMIO interface.
//  - ofs_plat_host_chan_@group@_as_axi_mem_with_dual_mmio - host memory,
//    read/write MMIO and a second write-only MMIO interface.
//

//
// Host memory as AXI memory (no MMIO).
//
module ofs_plat_host_chan_@group@_as_axi_mem
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0,

    // Added for compatibility with other native host channel interfaces,
    // such as PCIe TLP AXI-S. They are ignored in CCI-P, since responses
    // are necessarily sorted in order to guarantee that AXI-MM transactions
    // split to fit in CCI-P request sizes are returned in order.
    parameter SORT_READ_RESPONSES = 1,
    parameter SORT_WRITE_RESPONSES = 1,
    parameter BUFFER_READ_RESPONSES = 0
    )
   (
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    ofs_plat_axi_mem_if.to_source_clk host_mem_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    ofs_plat_host_ccip_if ccip_mmio();

    ofs_plat_host_chan_@group@_as_axi_mem_impl
     #(
       .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
       .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
       )
     impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .ccip_mmio,
        .afu_clk,
        .afu_reset_n
        );

    // Tie off MMIO
    assign ccip_mmio.sTx = t_if_ccip_Tx'(0);

endmodule // ofs_plat_host_chan_@group@_as_axi_mem


//
// Host memory and FPGA MMIO source as AXI. The width of the MMIO
// port is determined by the parameters bound to mmio_to_afu.
//
module ofs_plat_host_chan_@group@_as_axi_mem_with_mmio
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0,

    // Added for compatibility with other native host channel interfaces,
    // such as PCIe TLP AXI-S. They are ignored in CCI-P, since responses
    // are necessarily sorted in order to guarantee that AXI-MM transactions
    // split to fit in CCI-P request sizes are returned in order.
    parameter SORT_READ_RESPONSES = 1,
    parameter SORT_WRITE_RESPONSES = 1,
    parameter BUFFER_READ_RESPONSES = 0
    )
   (
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    ofs_plat_axi_mem_if.to_source_clk host_mem_to_afu,
    ofs_plat_axi_mem_lite_if.to_sink_clk mmio_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    ofs_plat_host_ccip_if ccip_mmio();

    ofs_plat_host_chan_@group@_as_axi_mem_impl
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
        )
      impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .ccip_mmio,
        .afu_clk,
        .afu_reset_n
        );

    // Internal MMIO AXI interface
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_to_afu)
        )
      mmio_if();

    // Do the CCI-P MMIO to AXI mapping
    ofs_plat_map_ccip_as_axi_mmio
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .MAX_OUTSTANDING_MMIO_RD_REQS(ccip_@group@_cfg_pkg::MAX_OUTSTANDING_MMIO_RD_REQS)
        )
      axi_host_mmio
       (
        .to_fiu(ccip_mmio),
        .mmio_to_afu(mmio_if),

        .afu_clk(host_mem_to_afu.clk),
        .afu_reset_n(host_mem_to_afu.reset_n)
        );

    // Add register stages, as requested. Force an extra one for timing.
    ofs_plat_axi_mem_lite_if_reg_source_clk
      #(
        .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
        )
      reg_mmio
       (
        .mem_source(mmio_if),
        .mem_sink(mmio_to_afu)
        );

endmodule // ofs_plat_host_chan_@group@_as_axi_mem_with_mmio


//
// Host memory, FPGA MMIO source and a second write-only MMIO as AXI.
// The widths of the MMIO ports are determined by the interface parameters
// to mmio_to_afu and mmio_wr_to_afu.
//
module ofs_plat_host_chan_@group@_as_axi_mem_with_dual_mmio
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0,

    // Added for compatibility with other native host channel interfaces,
    // such as PCIe TLP AXI-S. They are ignored in CCI-P, since responses
    // are necessarily sorted in order to guarantee that AXI-MM transactions
    // split to fit in CCI-P request sizes are returned in order.
    parameter SORT_READ_RESPONSES = 1,
    parameter SORT_WRITE_RESPONSES = 1,
    parameter BUFFER_READ_RESPONSES = 0
    )
   (
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    ofs_plat_axi_mem_if.to_source_clk host_mem_to_afu,
    ofs_plat_axi_mem_lite_if.to_sink_clk mmio_to_afu,
    ofs_plat_axi_mem_lite_if.to_sink_clk mmio_wr_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    ofs_plat_host_ccip_if ccip_mmio();

    ofs_plat_host_chan_@group@_as_axi_mem_impl
     #(
       .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
       .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
       )
     impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .ccip_mmio,
        .afu_clk,
        .afu_reset_n
        );

    // Internal MMIO AXI lite interface
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_to_afu)
        )
      mmio_if();

    // Do the CCI-P MMIO to AXI mapping
    ofs_plat_map_ccip_as_axi_mmio
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .MAX_OUTSTANDING_MMIO_RD_REQS(ccip_@group@_cfg_pkg::MAX_OUTSTANDING_MMIO_RD_REQS)
        )
      axi_host_mmio
       (
        .to_fiu(ccip_mmio),
        .mmio_to_afu(mmio_if),

        .afu_clk(host_mem_to_afu.clk),
        .afu_reset_n(host_mem_to_afu.reset_n)
        );

    // Add register stages, as requested. Force an extra one for timing.
    ofs_plat_axi_mem_lite_if_reg_source_clk
      #(
        .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
        )
      reg_mmio
       (
        .mem_source(mmio_if),
        .mem_sink(mmio_to_afu)
        );

    // Internal second (write only) MMIO AXI interface
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_wr_to_afu)
        )
      mmio_wr_if();

    // Do the CCI-P MMIO to AXI mapping
    ofs_plat_map_ccip_as_axi_mmio_wo
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .MAX_OUTSTANDING_MMIO_RD_REQS(ccip_@group@_cfg_pkg::MAX_OUTSTANDING_MMIO_RD_REQS)
        )
      axi_host_mmio_wr
       (
        .to_fiu(ccip_mmio),
        .mmio_to_afu(mmio_wr_if),

        .afu_clk(host_mem_to_afu.clk),
        .afu_reset_n(host_mem_to_afu.reset_n)
        );

    // Add register stages, as requested. Force an extra one for timing.
    ofs_plat_axi_mem_lite_if_reg_source_clk
      #(
        .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
        )
      reg_mmio_wr
       (
        .mem_source(mmio_wr_if),
        .mem_sink(mmio_wr_to_afu)
        );

endmodule // ofs_plat_host_chan_@group@_as_axi_mem_with_dual_mmio


// ========================================================================
//
//  Internal implementation.
//
// ========================================================================

//
// Map CCI-P to target clock and then to the host memory AXI interface.
// Also return the CCI-P ports needed for mapping MMIO to AXI.
//
module ofs_plat_host_chan_@group@_as_axi_mem_impl
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0
    )
   (
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    ofs_plat_axi_mem_if.to_source_clk host_mem_to_afu,

    // Export a CCI-P port for MMIO mapping
    ofs_plat_host_ccip_if.to_afu ccip_mmio,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    //
    // Connect to a CCI-P stream in which all write responses are packed.
    // Responses may still be out of order. Sorting will be handled in
    // ofs_plat_map_ccip_as_axi_host_mem below, where sorting and
    // clock crossing can share a buffer.
    //
    ofs_plat_host_ccip_if packed_ccip_if();

    ofs_plat_host_chan_@group@_as_ccip
      #(
        .MERGE_UNPACKED_WRITE_RESPONSES(1)
        )
      ccip_packed
       (
        .to_fiu,
        .to_afu(packed_ccip_if),
        .afu_clk(),
        .afu_reset_n()
        );

    //
    // Split CCI-P into separate host memory and MMIO interfaces.
    //
    ofs_plat_host_ccip_if host_mem_ccip_if();
    ofs_plat_shim_ccip_split_mmio split_mmio
       (
        .to_fiu(packed_ccip_if),
        .host_mem(host_mem_ccip_if),
        .mmio(ccip_mmio)
        );

    //
    // Now we can map to AXI.
    //
    ofs_plat_map_ccip_as_axi_host_mem
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .MAX_ACTIVE_RD_LINES(ccip_@group@_cfg_pkg::C0_MAX_BW_ACTIVE_LINES[0]),
        .MAX_ACTIVE_WR_LINES(ccip_@group@_cfg_pkg::C1_MAX_BW_ACTIVE_LINES[0]),
        .BYTE_EN_SUPPORTED(ccip_@group@_cfg_pkg::BYTE_EN_SUPPORTED),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
        )
      axi_host_mem
       (
        .to_fiu(host_mem_ccip_if),
        .host_mem_to_afu,
        .afu_clk,
        .afu_reset_n
        );

endmodule // ofs_plat_host_chan_@group@_as_axi_mem
