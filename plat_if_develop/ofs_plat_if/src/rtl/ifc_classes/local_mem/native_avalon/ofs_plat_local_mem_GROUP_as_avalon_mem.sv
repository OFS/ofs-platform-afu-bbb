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
// where the native interface is already Avalon.
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
    ofs_plat_avalon_mem_if.to_sink to_fiu,
    ofs_plat_avalon_mem_if.to_source_clk to_afu
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

    // ====================================================================
    //
    // While clocking and register stage insertion are logically
    // independent, considering them together leads to an important
    // optimization. The clock crossing FIFO has a large buffer that
    // can be used to turn the standard Avalon MM waitrequest signal into
    // an almost full protocol. The buffer stages become a simple
    // pipeline.
    //
    // When there is no clock crossing FIFO, all register stages must
    // honor the waitrequest protocol.
    //
    // ====================================================================

    //
    // How many register stages should be inserted for timing?
    //
    function automatic int numTimingRegStages();
        // Were timing registers requested?
        int n_stages = ADD_TIMING_REG_STAGES;

        // Override the register request if a clock crossing is being
        // inserted here.
        if (ADD_CLOCK_CROSSING)
        begin
            // Use at least the recommended number of stages
            if (`OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_SUGGESTED_TIMING_REG_STAGES > n_stages)
            begin
                n_stages = `OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_SUGGESTED_TIMING_REG_STAGES;
            end
        end

        return n_stages;
    endfunction

    localparam NUM_TIMING_REG_STAGES = numTimingRegStages();

    // ====================================================================
    //
    // The AFU's burst counter may be a different size than the FIU's
    // counter. If the AFU counter is larger then map AFU bursts to
    // FIU-sized chunks.
    //
    // ====================================================================

    ofs_plat_avalon_mem_if
      #(
        .ADDR_WIDTH(to_afu.ADDR_WIDTH_),
        // The AFU may pick a data width narrower than the FIU. Reduce it here.
        .DATA_WIDTH(to_fiu.DATA_WIDTH_),
        .MASKED_SYMBOL_WIDTH(to_afu.MASKED_SYMBOL_WIDTH_),
        .BURST_CNT_WIDTH(to_afu.BURST_CNT_WIDTH_),
        .USER_WIDTH(to_afu.USER_WIDTH_)
        )
      afu_burst_if();

    // synthesis translate_off
    initial
    begin
        if (to_afu.DATA_WIDTH_ > to_fiu.DATA_WIDTH_)
        begin
            $fatal(2, "** ERROR ** %m: AFU memory DATA_WIDTH (%0d) is wider than FIU (%0d)!",
                   to_afu.DATA_WIDTH_, to_fiu.DATA_WIDTH_);
        end
    end
    // synthesis translate_on

    // Connect to the to_afu instance, including passing the clock.
    ofs_plat_avalon_mem_if_connect_sink_clk conn_to_afu
       (
        .mem_source(to_afu),
        .mem_sink(afu_burst_if)
        );

    ofs_plat_avalon_mem_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(to_fiu)
        )
        afu_resp_if();

    generate
        if (to_afu.BURST_CNT_WIDTH_ <= to_fiu.BURST_CNT_WIDTH_)
        begin : nb
            // AFU's burst count is no larger than the FIU's. Just wire
            // the connection to the next stage.
            ofs_plat_avalon_mem_if_connect_sink_clk conn
               (
                .mem_source(afu_burst_if),
                .mem_sink(afu_resp_if)
                );
        end
        else
        begin : b
            // AFU bursts counts may be too large for the FIU.
            assign afu_burst_if.clk = afu_resp_if.clk;
            assign afu_burst_if.reset_n = afu_resp_if.reset_n;
            assign afu_burst_if.instance_number = afu_resp_if.instance_number;

            ofs_plat_avalon_mem_if_map_bursts
              #(
                .UFLAG_NO_REPLY(ofs_plat_local_mem_avalon_mem_pkg::LM_AVALON_UFLAG_NO_REPLY)
                )
              map_bursts
               (
                .mem_source(afu_burst_if),
                .mem_sink(afu_resp_if)
                );
        end
    endgenerate


    //
    // Native Avalon interfaces don't have user fields or write responses.
    // Synthesize them here. The extra logic will be dropped by Quartus if
    // the AFU doesn't consume the result.
    //
    // At this point:
    //  - Synthesize write responses. Most Avalon memory interfaces won't
    //    generate a write response. Due to the ordered, shared read/write
    //    bus, the point at which responses are generated in the pipeline
    //    doesn't affect the result.
    //  - Decorate read responses with readresponseuser.
    //
    ofs_plat_avalon_mem_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(to_fiu)
        )
        afu_mem_if();

    assign afu_resp_if.clk = afu_mem_if.clk;
    assign afu_resp_if.reset_n = afu_mem_if.reset_n;
    assign afu_resp_if.instance_number = afu_mem_if.instance_number;

    ofs_plat_avalon_mem_if_user_ext
      #(
        .RD_RESP_USER_ENTRIES(`OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_MAX_BW_ACTIVE_LINES_RD)
        )
      user_ext
       (
        .mem_source(afu_resp_if),
        .mem_sink(afu_mem_if)
        );

    ofs_plat_avalon_mem_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(to_fiu)
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
            ofs_plat_avalon_mem_if_reg_sink_clk
              #(
                .N_REG_STAGES(NUM_TIMING_REG_STAGES)
                )
              mem_pipe
               (
                .mem_source(afu_mem_if),
                .mem_sink(fiu_with_reset_if)
                );
        end
        else
        begin : cc
            // We assume that a single waitrequest signal can propagate faster
            // than the entire bus, so limit the number of stages.
            localparam NUM_WAITREQUEST_STAGES =
                // If pipeline is 4 stages or fewer then use the pipeline depth.
                (NUM_TIMING_REG_STAGES <= 4 ? NUM_TIMING_REG_STAGES :
                    // Up to depth 16 pipelines, use 4 waitrequest stages.
                    // Beyond 16 stages, set the waitrequest depth to 1/4 the
                    // base pipeline depth.
                    (NUM_TIMING_REG_STAGES <= 16 ? 4 : (NUM_TIMING_REG_STAGES >> 2)));

            // A few extra stages to avoid off-by-one errors. There is plenty of
            // space in the FIFO, so this has no performance consequences.
            localparam NUM_EXTRA_STAGES = (NUM_TIMING_REG_STAGES != 0) ? 4 : 0;

            // Set the almost full threshold to satisfy the buffering pipeline depth
            // plus the depth of the waitrequest pipeline plus a little extra to
            // avoid having to worry about off-by-one errors.
            localparam NUM_ALMFULL_SLOTS = NUM_TIMING_REG_STAGES +
                                           NUM_WAITREQUEST_STAGES +
                                           NUM_EXTRA_STAGES;


            //
            // Cross to the specified clock.
            //
            ofs_plat_avalon_mem_if
              #(
                `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(to_fiu),
                .WAIT_REQUEST_ALLOWANCE(NUM_WAITREQUEST_STAGES)
                )
                mem_cross_if();

            assign mem_cross_if.clk = afu_clk;
            assign mem_cross_if.instance_number = to_fiu.instance_number;

            assign afu_mem_if.clk = mem_cross_if.clk;
            assign afu_mem_if.reset_n = mem_cross_if.reset_n;
            assign afu_mem_if.instance_number = mem_cross_if.instance_number;

            // Add requested register stages on the AFU side of the clock crossing.
            // In this case the register stages are a simple pipeline because
            // the clock crossing FIFO reserves space for these stages to drain
            // after waitrequest is asserted.
            ofs_plat_avalon_mem_if_reg_simple
              #(
                .N_REG_STAGES(NUM_TIMING_REG_STAGES),
                .N_WAITREQUEST_STAGES(NUM_WAITREQUEST_STAGES)
                )
              mem_pipe
               (
                .mem_source(afu_mem_if),
                .mem_sink(mem_cross_if)
                );

            // Generate a local reset for timing. This isn't actually a clock
            // crossing reset. We use it because it relaxes the timing on the
            // entire local memory domain here. Waitrequest will be asserted
            // during this reset, so the delay is safe.
            ofs_plat_prim_clock_crossing_reset local_reset
               (
                .clk_src(afu_clk),
                .clk_dst(afu_clk),
                .reset_in(afu_reset_n),
                .reset_out(mem_cross_if.reset_n)
                );

            // synthesis translate_off
            always_ff @(negedge afu_clk)
            begin
                if (afu_reset_n === 1'bx)
                begin
                    $fatal(2, "** ERROR ** %m: afu_reset_n port is uninitialized!");
                end
            end
            // synthesis translate_on

            ofs_plat_avalon_mem_if
              #(
                `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(to_fiu)
                )
                fiu_reg_if();

            ofs_plat_avalon_mem_if_async_shim
              #(
                .COMMAND_ALMFULL_THRESHOLD(NUM_ALMFULL_SLOTS)
                )
              mem_async_shim
               (
                .mem_source(mem_cross_if),
                .mem_sink(fiu_reg_if)
                );

            //
            // Register stages for timing at the FIU edge.
            //
            ofs_plat_avalon_mem_if_reg_sink_clk
              #(
                .N_REG_STAGES(NUM_TIMING_REG_STAGES)
                )
              fiu_reg
               (
                .mem_source(fiu_reg_if),
                .mem_sink(fiu_with_reset_if)
                );
        end
    endgenerate


    //
    // Connect to the FIU, adding AFU soft reset
    //
    ofs_plat_avalon_mem_if_connect fiu_conn
       (
        .mem_source(fiu_with_reset_if),
        .mem_sink(to_fiu)
        );

endmodule // ofs_plat_local_mem_@group@_as_avalon_mem
