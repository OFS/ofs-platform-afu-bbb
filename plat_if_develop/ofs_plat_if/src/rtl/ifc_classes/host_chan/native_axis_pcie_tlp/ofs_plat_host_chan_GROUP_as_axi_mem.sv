// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Export a PCIe TLP native host_chan interface to an AFU as AXI interfaces.
// There are three AXI interfaces: host memory source, MMIO (FPGA memory
// sink) and write-only MMIO sink. The write-only variant can be useful
// for 512 bit MMIO.
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
    // When non-zero, add a clock crossing to move the AFU
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0,

    // Should read or write responses be returned in the order they were
    // requested? Read responses are ordered by default because a single
    // request may be broken into multiple PCIe unordered transactions,
    // which would violate AXI response ordering rules for a single request.
    parameter SORT_READ_RESPONSES = 1,
    parameter SORT_WRITE_RESPONSES = 0,

    // Should the PIM guarantee that every outstanding read response
    // has a buffer slot inside the PIM? When a ROB is needed to sort
    // responses this property is guaranteed. When responses are already
    // sorted, there is no default buffering inside the PIM. Some AFUs
    // depend on a buffer to avoid deadlocks. For example, an AFU that
    // routes read responses back as writes can deadlock if the read
    // and write request channels have shared control logic. In that case,
    // backed up read responses may inibit writes, thus deadlocking.
    // Setting BUFFER_READ_RESPONSES guarantees a home for all read
    // responses inside the PIM.
    parameter BUFFER_READ_RESPONSES = 0
    )
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu,

    ofs_plat_axi_mem_if.to_source_clk host_mem_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    ofs_plat_host_chan_@group@_as_axi_mem_enc
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .SORT_READ_RESPONSES(SORT_READ_RESPONSES),
        .SORT_WRITE_RESPONSES(SORT_WRITE_RESPONSES),
        .BUFFER_READ_RESPONSES(BUFFER_READ_RESPONSES)
        )
      e
       (
        .to_fiu,
        .host_mem_to_afu,
        .afu_clk,
        .afu_reset_n,
        .allow_dm_enc(1'b1)
        );

endmodule // ofs_plat_host_chan_@group@_as_axi_mem


//
// Host memory as AXI memory (no MMIO). Adds an input to control data mover
// vs. power user encoding.
//
module ofs_plat_host_chan_@group@_as_axi_mem_enc
  #(
    // When non-zero, add a clock crossing to move the AFU
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0,

    // Should read or write responses be returned in the order they were
    // requested? Read responses are ordered by default because a single
    // request may be broken into multiple PCIe unordered transactions,
    // which would violate AXI response ordering rules for a single request.
    parameter SORT_READ_RESPONSES = 1,
    parameter SORT_WRITE_RESPONSES = 0,

    // Should the PIM guarantee that every outstanding read response
    // has a buffer slot inside the PIM? When a ROB is needed to sort
    // responses this property is guaranteed. When responses are already
    // sorted, there is no default buffering inside the PIM. Some AFUs
    // depend on a buffer to avoid deadlocks. For example, an AFU that
    // routes read responses back as writes can deadlock if the read
    // and write request channels have shared control logic. In that case,
    // backed up read responses may inibit writes, thus deadlocking.
    // Setting BUFFER_READ_RESPONSES guarantees a home for all read
    // responses inside the PIM.
    parameter BUFFER_READ_RESPONSES = 0
    )
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu,

    ofs_plat_axi_mem_if.to_source_clk host_mem_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n,

    // Allow Data Mover encoding?
    input  logic allow_dm_enc
    );

    // Internal dummy MMIO AXI interfaces. They are required by the
    // internal mapper but will be dropped by Quartus.
    ofs_plat_axi_mem_lite_if
      #(
        `HOST_CHAN_@GROUP@_AXI_MMIO_PARAMS(64)
        )
      axi_mmio();

    assign axi_mmio.clk = host_mem_to_afu.clk;
    assign axi_mmio.reset_n = host_mem_to_afu.reset_n;
    assign axi_mmio.instance_number = to_fiu.instance_number;

    ofs_plat_axi_mem_lite_if
      #(
        `HOST_CHAN_@GROUP@_AXI_MMIO_PARAMS(64)
        )
      axi_wo_mmio();

    assign axi_wo_mmio.clk = host_mem_to_afu.clk;
    assign axi_wo_mmio.reset_n = host_mem_to_afu.reset_n;
    assign axi_wo_mmio.instance_number = to_fiu.instance_number;

    ofs_plat_host_chan_@group@_as_axi_mem_impl
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .SORT_READ_RESPONSES(SORT_READ_RESPONSES),
        .SORT_WRITE_RESPONSES(SORT_WRITE_RESPONSES),
        .BUFFER_READ_RESPONSES(BUFFER_READ_RESPONSES)
        )
     impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .axi_mmio,
        .axi_wo_mmio,
        .afu_clk,
        .afu_reset_n,
        .allow_dm_enc
        );

    // Tie off MMIO
    always_comb
    begin
        axi_mmio.awready = 1'b1;
        axi_mmio.wready = 1'b1;
        axi_mmio.bvalid = 1'b0;
        axi_mmio.arready = 1'b1;
        axi_mmio.rvalid = 1'b0;

        axi_wo_mmio.awready = 1'b1;
        axi_wo_mmio.wready = 1'b1;
        axi_wo_mmio.bvalid = 1'b0;
        axi_wo_mmio.arready = 1'b1;
        axi_wo_mmio.rvalid = 1'b0;
    end

endmodule // ofs_plat_host_chan_@group@_as_axi_mem_enc


//
// Host memory and FPGA MMIO source as AXI. The width of the MMIO
// port is determined by the parameters bound to mmio_to_afu.
//
module ofs_plat_host_chan_@group@_as_axi_mem_with_mmio
  #(
    // When non-zero, add a clock crossing to move the AFU
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0,

    // Should read or write responses be returned in the order they were
    // requested? Read responses are ordered by default because a single
    // request may be broken into multiple PCIe unordered transactions,
    // which would violate AXI response ordering rules for a single request.
    parameter SORT_READ_RESPONSES = 1,
    parameter SORT_WRITE_RESPONSES = 0,

    // Should the PIM guarantee that every outstanding read response
    // has a buffer slot inside the PIM? When a ROB is needed to sort
    // responses this property is guaranteed. When responses are already
    // sorted, there is no default buffering inside the PIM. Some AFUs
    // depend on a buffer to avoid deadlocks. For example, an AFU that
    // routes read responses back as writes can deadlock if the read
    // and write request channels have shared control logic. In that case,
    // backed up read responses may inibit writes, thus deadlocking.
    // Setting BUFFER_READ_RESPONSES guarantees a home for all read
    // responses inside the PIM.
    parameter BUFFER_READ_RESPONSES = 0
    )
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu,

    ofs_plat_axi_mem_if.to_source_clk host_mem_to_afu,
    ofs_plat_axi_mem_lite_if.to_sink_clk mmio_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );


    ofs_plat_host_chan_@group@_as_axi_mem_with_mmio_enc
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .SORT_READ_RESPONSES(SORT_READ_RESPONSES),
        .SORT_WRITE_RESPONSES(SORT_WRITE_RESPONSES),
        .BUFFER_READ_RESPONSES(BUFFER_READ_RESPONSES)
        )
      e
       (
        .to_fiu,
        .host_mem_to_afu,
        .mmio_to_afu,
        .afu_clk,
        .afu_reset_n,
        .allow_dm_enc(1'b1)
        );

endmodule // ofs_plat_host_chan_@group@_as_axi_mem_with_mmio


//
// Host memory and FPGA MMIO source as AXI. The width of the MMIO
// port is determined by the parameters bound to mmio_to_afu.
//
// Adds an input to control data mover vs. power user encoding.
//
module ofs_plat_host_chan_@group@_as_axi_mem_with_mmio_enc
  #(
    // When non-zero, add a clock crossing to move the AFU
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0,

    // Should read or write responses be returned in the order they were
    // requested? Read responses are ordered by default because a single
    // request may be broken into multiple PCIe unordered transactions,
    // which would violate AXI response ordering rules for a single request.
    parameter SORT_READ_RESPONSES = 1,
    parameter SORT_WRITE_RESPONSES = 0,

    // Should the PIM guarantee that every outstanding read response
    // has a buffer slot inside the PIM? When a ROB is needed to sort
    // responses this property is guaranteed. When responses are already
    // sorted, there is no default buffering inside the PIM. Some AFUs
    // depend on a buffer to avoid deadlocks. For example, an AFU that
    // routes read responses back as writes can deadlock if the read
    // and write request channels have shared control logic. In that case,
    // backed up read responses may inibit writes, thus deadlocking.
    // Setting BUFFER_READ_RESPONSES guarantees a home for all read
    // responses inside the PIM.
    parameter BUFFER_READ_RESPONSES = 0
    )
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu,

    ofs_plat_axi_mem_if.to_source_clk host_mem_to_afu,
    ofs_plat_axi_mem_lite_if.to_sink_clk mmio_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n,

    // Allow Data Mover encoding?
    input  logic allow_dm_enc
    );

    // Internal MMIO AXI interface
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_to_afu)
        )
      axi_mmio();

    assign axi_mmio.clk = to_fiu.clk;
    assign axi_mmio.reset_n = to_fiu.reset_n;
    assign axi_mmio.instance_number = to_fiu.instance_number;

    // Internal dummy MMIO write only AXI interface. It is required
    // by the internal mapper but will be dropped by Quartus.
    ofs_plat_axi_mem_lite_if
      #(
        `HOST_CHAN_@GROUP@_AXI_MMIO_PARAMS(64)
        )
      axi_wo_mmio();

    assign axi_wo_mmio.clk = to_fiu.clk;
    assign axi_wo_mmio.reset_n = to_fiu.reset_n;
    assign axi_wo_mmio.instance_number = to_fiu.instance_number;

    ofs_plat_host_chan_@group@_as_axi_mem_impl
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .SORT_READ_RESPONSES(SORT_READ_RESPONSES),
        .SORT_WRITE_RESPONSES(SORT_WRITE_RESPONSES),
        .BUFFER_READ_RESPONSES(BUFFER_READ_RESPONSES)
        )
      impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .axi_mmio,
        .axi_wo_mmio,
        .afu_clk,
        .afu_reset_n,
        .allow_dm_enc
        );

    // Add clock crossing or register stages, as requested.
    // Force an extra one for timing.
    generate
        if (ADD_CLOCK_CROSSING)
        begin : cc
            ofs_plat_axi_mem_lite_if
              #(
                `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_to_afu)
                )
              axi_mmio_afu_clk();

            ofs_plat_axi_mem_lite_if_async_shim_set_sink
              #(
                .ADD_TIMING_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              cc_mmio
               (
                .mem_source(axi_mmio),
                .mem_sink(axi_mmio_afu_clk),
                .sink_clk(host_mem_to_afu.clk),
                .sink_reset_n(host_mem_to_afu.reset_n)
                );

            ofs_plat_axi_mem_lite_if_reg_source_clk
              #(
                .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              reg_mmio
               (
                .mem_source(axi_mmio_afu_clk),
                .mem_sink(mmio_to_afu)
                );
        end
        else
        begin : nc
            ofs_plat_axi_mem_lite_if_reg_source_clk
              #(
                .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              reg_mmio
               (
                .mem_source(axi_mmio),
                .mem_sink(mmio_to_afu)
                );
        end
    endgenerate


    // Tie off dummy write-only MMIO
    always_comb
    begin
        axi_wo_mmio.awready = 1'b1;
        axi_wo_mmio.wready = 1'b1;
        axi_wo_mmio.bvalid = 1'b0;
        axi_wo_mmio.arready = 1'b1;
        axi_wo_mmio.rvalid = 1'b0;
    end

endmodule // ofs_plat_host_chan_@group@_as_axi_mem_with_mmio_enc


//
// Host memory, FPGA MMIO source and a second write-only MMIO as AXI.
// The widths of the MMIO ports are determined by the interface parameters
// to mmio_to_afu and mmio_wr_to_afu.
//
module ofs_plat_host_chan_@group@_as_axi_mem_with_dual_mmio
  #(
    // When non-zero, add a clock crossing to move the AFU
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0,

    // Should read or write responses be returned in the order they were
    // requested? Read responses are ordered by default because a single
    // request may be broken into multiple PCIe unordered transactions,
    // which would violate AXI response ordering rules for a single request.
    parameter SORT_READ_RESPONSES = 1,
    parameter SORT_WRITE_RESPONSES = 0,

    // Should the PIM guarantee that every outstanding read response
    // has a buffer slot inside the PIM? When a ROB is needed to sort
    // responses this property is guaranteed. When responses are already
    // sorted, there is no default buffering inside the PIM. Some AFUs
    // depend on a buffer to avoid deadlocks. For example, an AFU that
    // routes read responses back as writes can deadlock if the read
    // and write request channels have shared control logic. In that case,
    // backed up read responses may inibit writes, thus deadlocking.
    // Setting BUFFER_READ_RESPONSES guarantees a home for all read
    // responses inside the PIM.
    parameter BUFFER_READ_RESPONSES = 0
    )
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu,

    ofs_plat_axi_mem_if.to_source_clk host_mem_to_afu,
    ofs_plat_axi_mem_lite_if.to_sink_clk mmio_to_afu,
    ofs_plat_axi_mem_lite_if.to_sink_clk mmio_wr_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    // Internal MMIO AXI interface
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_to_afu)
        )
      axi_mmio();

    assign axi_mmio.clk = to_fiu.clk;
    assign axi_mmio.reset_n = to_fiu.reset_n;
    assign axi_mmio.instance_number = to_fiu.instance_number;

    // Internal write-only MMIO AXI interface
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_wr_to_afu)
        )
      axi_wo_mmio();

    assign axi_wo_mmio.clk = to_fiu.clk;
    assign axi_wo_mmio.reset_n = to_fiu.reset_n;
    assign axi_wo_mmio.instance_number = to_fiu.instance_number;

    ofs_plat_host_chan_@group@_as_axi_mem_impl
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .SORT_READ_RESPONSES(SORT_READ_RESPONSES),
        .SORT_WRITE_RESPONSES(SORT_WRITE_RESPONSES),
        .BUFFER_READ_RESPONSES(BUFFER_READ_RESPONSES)
        )
      impl
       (
        .to_fiu,
        .host_mem_to_afu,
        .axi_mmio,
        .axi_wo_mmio,
        .afu_clk,
        .afu_reset_n,
        .allow_dm_enc(1'b1)
        );

    // Add clock crossing or register stages, as requested.
    // Force an extra one for timing.
    generate
        if (ADD_CLOCK_CROSSING)
        begin : cc
            ofs_plat_axi_mem_lite_if
              #(
                `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_to_afu)
                )
              axi_mmio_afu_clk();

            ofs_plat_axi_mem_lite_if
              #(
                `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mmio_wr_to_afu)
                )
              axi_wo_mmio_afu_clk();

            ofs_plat_axi_mem_lite_if_async_shim_set_sink
              #(
                .ADD_TIMING_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              cc_mmio
               (
                .mem_source(axi_mmio),
                .mem_sink(axi_mmio_afu_clk),
                .sink_clk(host_mem_to_afu.clk),
                .sink_reset_n(host_mem_to_afu.reset_n)
                );

            ofs_plat_axi_mem_lite_if_async_shim_set_sink
              #(
                .ADD_TIMING_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              cc_mmio_wo
               (
                .mem_source(axi_wo_mmio),
                .mem_sink(axi_wo_mmio_afu_clk),
                .sink_clk(host_mem_to_afu.clk),
                .sink_reset_n(host_mem_to_afu.reset_n)
                );

            ofs_plat_axi_mem_lite_if_reg_source_clk
              #(
                .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              reg_mmio
               (
                .mem_source(axi_mmio_afu_clk),
                .mem_sink(mmio_to_afu)
                );

            ofs_plat_axi_mem_lite_if_reg_source_clk
              #(
                .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              reg_mmio_wo
               (
                .mem_source(axi_wo_mmio_afu_clk),
                .mem_sink(mmio_wr_to_afu)
                );
        end
        else
        begin : nc
            ofs_plat_axi_mem_lite_if_reg_source_clk
              #(
                .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              reg_mmio
               (
                .mem_source(axi_mmio),
                .mem_sink(mmio_to_afu)
                );

            ofs_plat_axi_mem_lite_if_reg_source_clk
              #(
                .N_REG_STAGES(1 + ADD_TIMING_REG_STAGES)
                )
              reg_mmio_wo
               (
                .mem_source(axi_wo_mmio),
                .mem_sink(mmio_wr_to_afu)
                );
        end
    endgenerate

endmodule // ofs_plat_host_chan_@group@_as_axi_mem_with_dual_mmio


// ========================================================================
//
//  Internal implementation.
//
// ========================================================================

//
// Map AXI-MM to target clock and then to the host memory PCIe TLP
// interface.
//
module ofs_plat_host_chan_@group@_as_axi_mem_impl
  #(
    // When non-zero, add a clock crossing to move the AFU interfaces
    // to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0,

    // Should read or write responses be returned in the order they were
    // requested? Read responses are ordered by default because a single
    // request may be broken into multiple PCIe unordered transactions,
    // which would violate AXI response ordering rules for a single request.
    parameter SORT_READ_RESPONSES = 1,
    parameter SORT_WRITE_RESPONSES = 0,

    // Should the PIM guarantee that every outstanding read response
    // has a buffer slot inside the PIM? When a ROB is needed to sort
    // responses this property is guaranteed. When responses are already
    // sorted, there is no default buffering inside the PIM. Some AFUs
    // depend on a buffer to avoid deadlocks. For example, an AFU that
    // routes read responses back as writes can deadlock if the read
    // and write request channels have shared control logic. In that case,
    // backed up read responses may inibit writes, thus deadlocking.
    // Setting BUFFER_READ_RESPONSES guarantees a home for all read
    // responses inside the PIM.
    parameter BUFFER_READ_RESPONSES = 0
    )
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu,

    ofs_plat_axi_mem_if.to_source_clk host_mem_to_afu,

    // Export an AXI lite port for MMIO mapping
    ofs_plat_axi_mem_lite_if.to_sink axi_mmio,
    // Export a second AXI lite port for MMIO write-only mapping. This
    // may be used when the AFU will receive wide MMIO writes but only
    // respond with narrow (e.g. 64 bit) MMIO reads.
    ofs_plat_axi_mem_lite_if.to_sink axi_wo_mmio,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n,

    // Allow Data Mover TLP encoding?
    input  logic allow_dm_enc
    );

    localparam int MAX_BW_ACTIVE_RD_LINES =
                       ofs_plat_host_chan_@group@_pcie_tlp_pkg::MAX_BW_ACTIVE_RD_LINES;
    localparam int MAX_BW_ACTIVE_WR_LINES =
                       ofs_plat_host_chan_@group@_pcie_tlp_pkg::MAX_BW_ACTIVE_WR_LINES;

    // ====================================================================
    //  Bind the proper clock to the AFU interface. If there is no clock
    //  crossing requested then it's just the FIU clock.
    // ====================================================================

    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(host_mem_to_afu)
        )
      axi_afu_clk_if();

    logic afu_reset_n_q = 1'b0;
    always @(posedge afu_clk)
    begin
        afu_reset_n_q <= afu_reset_n;
    end

    assign axi_afu_clk_if.clk = (ADD_CLOCK_CROSSING == 0) ? to_fiu.clk : afu_clk;
    assign axi_afu_clk_if.reset_n = (ADD_CLOCK_CROSSING == 0) ? to_fiu.reset_n : afu_reset_n_q;
    assign axi_afu_clk_if.instance_number = to_fiu.instance_number;

    // synthesis translate_off
    always_ff @(negedge axi_afu_clk_if.clk)
    begin
        if (axi_afu_clk_if.reset_n === 1'bx)
        begin
            $fatal(2, "** ERROR ** %m: axi_afu_clk_if.reset_n port is uninitialized!");
        end
    end
    // synthesis translate_on

    ofs_plat_axi_mem_if_connect_sink_clk
      conn_afu_clk
       (
        .mem_source(host_mem_to_afu),
        .mem_sink(axi_afu_clk_if)
        );


    // ====================================================================
    //  Cross to the FIU clock, sort responses and map bursts to FIU sizes.
    // ====================================================================

    // ofs_plat_axi_mem_if_async_rob records the ROB indices of read and
    // write requests in ID fields. The original values are recorded in the
    // ROB and returned to the source.
    localparam ROB_RID_WIDTH = $clog2(MAX_BW_ACTIVE_RD_LINES);
    localparam ROB_WID_WIDTH = $clog2(MAX_BW_ACTIVE_WR_LINES);

    // Maximum burst that fits in the largest allowed TLP packet
    localparam FIU_BURST_CNT_MAX = ofs_plat_host_chan_@group@_pcie_tlp_pkg::MAX_PAYLOAD_SIZE /
                                   host_mem_to_afu.DATA_WIDTH;

    ofs_plat_axi_mem_if
      #(
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN),
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_MEM_PARAMS(host_mem_to_afu),
        .BURST_CNT_WIDTH($clog2(FIU_BURST_CNT_MAX)),
        .USER_WIDTH(host_mem_to_afu.USER_WIDTH),
        .RID_WIDTH(ROB_RID_WIDTH),
        .WID_WIDTH(ROB_WID_WIDTH)
        )
      axi_fiu_clk_if();

    assign axi_fiu_clk_if.clk = to_fiu.clk;
    assign axi_fiu_clk_if.reset_n = to_fiu.reset_n;
    assign axi_fiu_clk_if.instance_number = to_fiu.instance_number;

    // The AXI interface is always sorted here, despite the AXI bus not
    // requiring sorted responses. We do this because large AXI bursts are
    // broken into smaller PCIe TLP bursts. These smaller PCIe bursts
    // might be reordered by the PCIe network. AXI requires that
    // responses for a single request be returned in order. In order
    // to guarantee this, we sort responses.
    ofs_plat_map_axi_mem_if_to_host_mem
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        // Add a reorder buffer if the responses aren't already sorted.
        .SORT_RESPONSES(ofs_plat_host_chan_@group@_fim_gasket_pkg::CPL_REORDER_EN == 0),
        .BUFFER_READ_RESPONSES(BUFFER_READ_RESPONSES),
        .MAX_ACTIVE_RD_LINES(MAX_BW_ACTIVE_RD_LINES),
        .MAX_ACTIVE_WR_LINES(MAX_BW_ACTIVE_WR_LINES),
        // Don't allow packets to cross 4KB pages due to PCIe requirement.
        .PAGE_SIZE(4096),
        .NUM_PAYLOAD_RCB_SEGS(ofs_plat_host_chan_@group@_pcie_tlp_pkg::NUM_PAYLOAD_RCB_SEGS)
        )
      hc
       (
        .mem_source(axi_afu_clk_if),
        .mem_sink(axi_fiu_clk_if)
        );


    // ====================================================================
    //  Basic mapping from AXI-MM to TLPs, all in the FIU clock domain.
    // ====================================================================

    // The AXI-MM interface (axi_fiu_clk_if) is in the FIU domain and
    // bursts are sized properly for PCIe. All that remains is to map
    // AXI-MM bursts to PCIe TLP.

    ofs_plat_host_chan_@group@_map_as_axi_mem_if tlp_as_axi_mem
       (
        .mem_source(axi_fiu_clk_if),
        .mmio_sink(axi_mmio),
        .mmio_wo_sink(axi_wo_mmio),
        .to_fiu_tlp(to_fiu),
        .allow_dm_enc
        );

endmodule // ofs_plat_host_chan_@group@_as_axi_mem
