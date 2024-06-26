// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Export a platform local_mem interface to an AFU as an AXI memory.
//
// The "as AXI" abstraction here allows an AFU to request the memory
// using a particular interface. The platform may offer multiple interfaces
// to the same underlying PR wires, instantiating protocol conversion
// shims as needed.
//

//
// This version of ofs_plat_local_mem_as_axi_mem works on platforms
// where the native interface is already AXI.
//

`include "ofs_plat_if.vh"

module ofs_plat_local_mem_@group@_as_axi_mem
  #(
    // When non-zero, add a clock crossing to move the AFU interface
    // to the passed in afu_clk.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages, typically for timing.
    parameter ADD_TIMING_REG_STAGES = 0,

    // Should read or write responses be returned in the order they were
    // requested? For now, we assume that AXI local memory interfaces
    // already return responses in order. They are defined so the interface
    // remains consistent with future devices that may return responses out
    // of order.
    parameter SORT_READ_RESPONSES = 1,
    parameter SORT_WRITE_RESPONSES = 1
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

    // The ports are named "to_fiu" and "to_afu" despite the AXI
    // to_sink/to_source naming because the PIM port naming is a
    // bus-independent abstraction. At top-level, PIM ports are
    // always to_fiu and to_afu.
    ofs_plat_axi_mem_if.to_sink to_fiu,
    ofs_plat_axi_mem_if.to_source_clk to_afu
    );

    // Combine AFU soft reset with the FIU local memory reset
    logic fiu_soft_reset_n = 1'b0;
    logic afu_reset_n_in_fiu_clk;

    ofs_plat_prim_clock_crossing_reset soft_reset
       (
        .clk_src(afu_clk),
        .clk_dst(to_fiu.clk),
        .reset_in(afu_reset_n),
        .reset_out(afu_reset_n_in_fiu_clk)
        );

    always @(posedge to_fiu.clk)
    begin
        fiu_soft_reset_n <= to_fiu.reset_n && afu_reset_n_in_fiu_clk;
    end

    //
    // How many register stages should be inserted for timing?
    //
    function automatic int numTimingRegStages();
        // Were timing registers requested?
        int n_stages = ADD_TIMING_REG_STAGES;

        // Use at least two stages
        if (n_stages < 2)
            n_stages = 2;

        // Use at least the recommended number of stages
        if (`OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_SUGGESTED_TIMING_REG_STAGES > n_stages)
        begin
            n_stages = `OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_SUGGESTED_TIMING_REG_STAGES;
        end

        return n_stages;
    endfunction

    localparam NUM_TIMING_REG_STAGES = numTimingRegStages();

    //
    // Connect to the to_afu instance, including passing the clock.
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(to_afu)
        )
      axi_afu_if();

    assign axi_afu_if.clk = (ADD_CLOCK_CROSSING == 0) ? to_fiu.clk : afu_clk;
    assign axi_afu_if.instance_number = to_fiu.instance_number;

    logic reset_n = 1'b0;
    always @(posedge axi_afu_if.clk)
    begin
        reset_n <= (ADD_CLOCK_CROSSING == 0) ? fiu_soft_reset_n : afu_reset_n;
    end

    assign axi_afu_if.reset_n = reset_n;

    ofs_plat_axi_mem_if_connect_sink_clk conn_to_afu
       (
        .mem_source(to_afu),
        .mem_sink(axi_afu_if)
        );


    //
    // Map AFU-sized bursts to FIU-sized bursts. (The AFU may generate larger
    // bursts than the FIU will accept.)
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_MEM_PARAMS(to_afu),
        .BURST_CNT_WIDTH(to_fiu.BURST_CNT_WIDTH),
        .RID_WIDTH(to_afu.RID_WIDTH),
        .WID_WIDTH(to_afu.WID_WIDTH),
        .USER_WIDTH(to_afu.USER_WIDTH)
        )
      axi_fiu_burst_if();

    assign axi_fiu_burst_if.clk = axi_afu_if.clk;
    assign axi_fiu_burst_if.reset_n = axi_afu_if.reset_n;
    assign axi_fiu_burst_if.instance_number = to_fiu.instance_number;

    ofs_plat_axi_mem_if_map_bursts
      #(
        .UFLAG_NO_REPLY(ofs_plat_local_mem_axi_mem_pkg::LM_AXI_UFLAG_NO_REPLY)
        )
      map_bursts
       (
        .mem_source(axi_afu_if),
        .mem_sink(axi_fiu_burst_if)
        );


    //
    // Preserve AFU user and extra ID bits and return them with responses.
    // The PIM adds extra state to AXI user fields that devices may not
    // implement.
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_MEM_PARAMS(to_afu),
        .BURST_CNT_WIDTH(to_fiu.BURST_CNT_WIDTH),
        .RID_WIDTH(to_fiu.RID_WIDTH),
        .WID_WIDTH(to_fiu.WID_WIDTH),
        .USER_WIDTH(to_fiu.USER_WIDTH)
        )
      axi_fiu_user_if();

    assign axi_fiu_user_if.clk = axi_afu_if.clk;
    assign axi_fiu_user_if.reset_n = axi_afu_if.reset_n;
    assign axi_fiu_user_if.instance_number = to_fiu.instance_number;

    ofs_plat_axi_mem_if_user_ext
      #(
        .FIM_USER_WIDTH(`OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_USER_WIDTH),
        // Don't trust the memory subsystem to preserve user bits
        .FORCE_USER_TO_ZERO(1),
        // Set RD/WR IDs to zero in requests, which causes the memory subsystem
        // to keep read and write channels ordered. The Intel AXI-MM interface
        // to memory does not maintain relative order of read and write channels.
        // It only guarantees order within the read or write channel when IDs match.
        // The current memory subsystem implementation performance is identical
        // with or without setting ID to zero, so we keep responses ordered.
        .FORCE_RD_ID_TO_ZERO(1),
        .FORCE_WR_ID_TO_ZERO(1)
        )
      map_user
       (
        .mem_source(axi_fiu_burst_if),
        .mem_sink(axi_fiu_user_if)
        );

    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(to_fiu)
        )
        fiu_with_reset_if();

    assign fiu_with_reset_if.clk = to_fiu.clk;
    assign fiu_with_reset_if.reset_n = fiu_soft_reset_n;
    assign fiu_with_reset_if.instance_number = to_fiu.instance_number;

    //
    // Clock crossing between AFU and FIU?
    //
    generate
        if (ADD_CLOCK_CROSSING == 0)
        begin : nc
            //
            // No clock crossing, maybe register stages.
            //
            ofs_plat_axi_mem_if_reg
              #(
                .N_REG_STAGES(NUM_TIMING_REG_STAGES)
                )
              mem_pipe
               (
                .mem_source(axi_fiu_user_if),
                .mem_sink(fiu_with_reset_if)
                );
        end
        else
        begin : cc
            //
            // Clock crossing to sink clock.
            //
            ofs_plat_axi_mem_if
              #(
                `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(to_fiu)
                )
              axi_fiu_clk_if();

            ofs_plat_axi_mem_if_async_shim
              #(
                .ADD_TIMING_REG_STAGES(NUM_TIMING_REG_STAGES),
                .NUM_READ_CREDITS(`OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_MAX_BW_ACTIVE_LINES_RD),
                .NUM_WRITE_CREDITS(`OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_MAX_BW_ACTIVE_LINES_WR)
                )
              async_shim
               (
                .mem_source(axi_fiu_user_if),
                .mem_sink(axi_fiu_clk_if)
                );


            //
            // Connect to the FIU
            //
            ofs_plat_axi_mem_if_reg_sink_clk
              #(
                .N_REG_STAGES(1)
                )
              mem_pipe
               (
                .mem_source(axi_fiu_clk_if),
                .mem_sink(fiu_with_reset_if)
                );
        end
    endgenerate


    //
    // Connect to the FIU, adding AFU soft reset
    //
    ofs_plat_axi_mem_if_connect fiu_conn
       (
        .mem_source(fiu_with_reset_if),
        .mem_sink(to_fiu)
        );

endmodule // ofs_plat_local_mem_@group@_as_axi_mem
