// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Export a platform local_mem interface to an AFU as an Avalon memory.
//
// The "as Avalon" abstraction here allows an AFU to request the memory
// using a particular interface. The platform may offer multiple interfaces
// to the same underlying PR wires, instantiating protocol conversion
// shims as needed.
//

//
// This version of ofs_plat_local_mem_as_avalon_mem works on platforms
// where the native interface is AXI-MM.
//

`include "ofs_plat_if.vh"

module ofs_plat_local_mem_@group@_as_avalon_mem
  #(
    // When non-zero, add a clock crossing to move the AFU interface
    // to the passed in afu_clk.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages, typically for timing.
    parameter ADD_TIMING_REG_STAGES = 0
    )
   (
    // AFU clock and reset must always be passed in, even when ADD_CLOCK_CROSSING
    // is 0. On systems with multiple AFU interfaces, the local memory reset can
    // not be driven globally by soft reset signals. The AFU-specific soft
    // reset bound to the memory is unknown, except to the AFU. afu_reset_n
    // is mapped below to the local memory's clock domain and drives reset
    // of the full stack instantiated here.
    input  logic afu_clk,
    input  logic afu_reset_n,

    // The ports are named "to_fiu" and "to_afu" despite the Avalon
    // to_sink/to_source naming because the PIM port naming is a
    // bus-independent abstraction. At top-level, PIM ports are
    // always to_fiu and to_afu.
    ofs_plat_axi_mem_if.to_sink to_fiu,
    ofs_plat_avalon_mem_if.to_source_clk to_afu
    );

    logic clk;
    logic reset_n;

    // AXI addresses are byte indices. Avalon are lines. Pad the AXI low
    // address bits with zero.
    localparam ADDR_BYTE_IDX_WIDTH = to_fiu.ADDR_WIDTH - to_afu.ADDR_WIDTH;

    // AXI bursts are 0 based, so one bit smaller than Avalon.
    localparam AXI_BURST_CNT_WIDTH = to_afu.BURST_CNT_WIDTH - 1;
    typedef logic [AXI_BURST_CNT_WIDTH-1 : 0] t_axi_burst_cnt;


    //
    // Register incoming Avalon interface
    //
    ofs_plat_avalon_mem_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(to_afu)
        )
      to_afu_reg();

    ofs_plat_avalon_mem_if_reg_sink_clk
      #(
        .N_REG_STAGES(1)
        )
      mem_reg
       (
        .mem_source(to_afu),
        .mem_sink(to_afu_reg)
        );


    //
    // Map the AFU's Avalon memory interface directly to AXI. We will
    // then use the PIM's AXI pipeline for burst mapping and clock
    // crossing.
    //
    ofs_plat_axi_mem_if
      #(
        .ADDR_WIDTH(to_fiu.ADDR_WIDTH),
        .DATA_WIDTH(to_fiu.DATA_WIDTH),
        // Avalon burst count of the source, mapped to AXI size
        .BURST_CNT_WIDTH(AXI_BURST_CNT_WIDTH),
        .RID_WIDTH(to_fiu.RID_WIDTH),
        .WID_WIDTH(to_fiu.WID_WIDTH),
        .USER_WIDTH(to_afu.USER_WIDTH),
        .MASKED_SYMBOL_WIDTH(to_fiu.MASKED_SYMBOL_WIDTH)
        )
      axi_afu_if();

    assign clk = axi_afu_if.clk;
    assign reset_n = axi_afu_if.reset_n;


    logic wr_is_sop;
    logic wr_is_eop;

    // AXI stream ready for a write request? At least the data bus must be ready.
    // The address bus must be available on SOP.
    wire axi_wr_ready = axi_afu_if.wready && (!wr_is_sop || axi_afu_if.awready);

    ofs_plat_prim_burstcount1_sop_tracker
      #(
        .BURST_CNT_WIDTH(to_afu.BURST_CNT_WIDTH)
        )
      afu_bursts
       (
        .clk,
        .reset_n,

        .flit_valid(to_afu_reg.write && axi_wr_ready),
        .burstcount(to_afu_reg.burstcount),

        .sop(wr_is_sop),
        .eop(wr_is_eop)
        );


    assign to_afu_reg.clk = axi_afu_if.clk;
    assign to_afu_reg.reset_n = axi_afu_if.reset_n;
    assign to_afu_reg.instance_number = axi_afu_if.instance_number;

    // Map AXI ready signals to Avalon, picking the appropriate channel(s) for the
    // request type.
    assign to_afu_reg.waitrequest = to_afu_reg.write ? !axi_wr_ready : !axi_afu_if.arready;

    always_comb
    begin
        // Write address channel
        axi_afu_if.awvalid = to_afu_reg.write && axi_wr_ready && wr_is_sop;
        axi_afu_if.aw = '0;
        axi_afu_if.aw.addr = { to_afu_reg.address, ADDR_BYTE_IDX_WIDTH'(0) };
        axi_afu_if.aw.len = t_axi_burst_cnt'(to_afu_reg.burstcount - 1);
        axi_afu_if.aw.size = $clog2(to_afu_reg.DATA_N_BYTES);
        axi_afu_if.aw.user = to_afu_reg.user;

        // Write data channel
        axi_afu_if.wvalid = to_afu_reg.write && axi_wr_ready;
        axi_afu_if.w = '0;
        axi_afu_if.w.data = to_afu_reg.writedata;
        axi_afu_if.w.strb = to_afu_reg.byteenable;
        axi_afu_if.w.last = wr_is_eop;
        axi_afu_if.w.user = to_afu_reg.user;

        // Read address channel
        axi_afu_if.arvalid = to_afu_reg.read && axi_afu_if.arready;
        axi_afu_if.ar = '0;
        axi_afu_if.ar.addr = { to_afu_reg.address, ADDR_BYTE_IDX_WIDTH'(0) };
        axi_afu_if.ar.len = t_axi_burst_cnt'(to_afu_reg.burstcount - 1);
        axi_afu_if.ar.size = $clog2(to_afu_reg.DATA_N_BYTES);
        axi_afu_if.ar.user = to_afu_reg.user;

        // Write response
        axi_afu_if.bready = 1'b1;
        to_afu_reg.writeresponsevalid = axi_afu_if.bvalid;
        to_afu_reg.writeresponse = '0;
        to_afu_reg.writeresponseuser = axi_afu_if.b.user;

        // Read response
        axi_afu_if.rready = 1'b1;
        to_afu_reg.readdatavalid = axi_afu_if.rvalid;
        to_afu_reg.readdata = axi_afu_if.r.data;
        to_afu_reg.response = '0;
        to_afu_reg.readresponseuser = axi_afu_if.r.user;
    end


    //
    // Burst mapping, clock crossing, etc.
    //
    ofs_plat_local_mem_@group@_as_axi_mem
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .SORT_READ_RESPONSES(1),
        .SORT_WRITE_RESPONSES(1)
        )
      axi_mapping
       (
        .to_afu(axi_afu_if),
        .to_fiu,
        .afu_clk,
        .afu_reset_n
        );

endmodule // ofs_plat_local_mem_@group@_as_avalon_mem
