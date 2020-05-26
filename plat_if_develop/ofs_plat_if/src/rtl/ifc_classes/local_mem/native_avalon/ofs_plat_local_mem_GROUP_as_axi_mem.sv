//
// Copyright (c) 2020, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

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
// where the native interface is Avalon.
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
    // requested? Native Avalon will already return responses in order,
    // so these don't matter in this case. They are defined so the interface
    // remains consistent with devices that return responses out of order.
    parameter SORT_READ_RESPONSES = 1,
    parameter SORT_WRITE_RESPONSES = 1
    )
   (
    // AFU clock for memory when a clock crossing is requested
    input  logic afu_clk,
    input  logic afu_reset_n,

    // The ports are named "to_fiu" and "to_afu" despite the Avalon
    // to_slave/to_master naming because the PIM port naming is a
    // bus-independent abstraction. At top-level, PIM ports are
    // always to_fiu and to_afu.
    ofs_plat_avalon_mem_if.to_slave to_fiu,
    ofs_plat_axi_mem_if.to_master_clk to_afu
    );

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


    //
    // Connect to the to_afu instance, including passing the clock.
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(to_afu)
        )
      axi_afu_if();

    assign axi_afu_if.clk = afu_mem_if.clk;
    assign axi_afu_if.reset_n = afu_mem_if.reset_n;
    assign axi_afu_if.instance_number = afu_mem_if.instance_number;

    ofs_plat_axi_mem_if_connect_slave_clk conn_to_afu
       (
        .mem_master(to_afu),
        .mem_slave(axi_afu_if)
        );


    //
    // Map AFU-sized bursts to FIU-sized bursts. (The AFU may generate larger
    // bursts than the FIU will accept.)
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_MEM_PARAMS(to_afu),
        // Avalon burst count of the slave, mapped to AXI size
        .BURST_CNT_WIDTH(to_fiu.BURST_CNT_WIDTH_ - 1),
        .RID_WIDTH(to_afu.RID_WIDTH_),
        .WID_WIDTH(to_afu.WID_WIDTH_),
        // Extra bit to tag bursts generated inside the burst mapper
        .USER_WIDTH(to_afu.USER_WIDTH_ + 1)
        )
      axi_fiu_burst_if();

    assign axi_fiu_burst_if.clk = afu_mem_if.clk;
    assign axi_fiu_burst_if.reset_n = afu_mem_if.reset_n;
    assign axi_fiu_burst_if.instance_number = afu_mem_if.instance_number;

    ofs_plat_axi_mem_if_map_bursts map_bursts
       (
        .mem_master(axi_afu_if),
        .mem_slave(axi_fiu_burst_if)
        );


    //
    // Map AXI master to Avalon split-bus read/write slave.
    //

    // Larger of RID/WID
    localparam ID_WIDTH = (to_afu.RID_WIDTH > to_afu.WID_WIDTH) ? to_afu.RID_WIDTH : to_afu.WID_WIDTH;
    // Avalon user width must hold AXI "id" and "user" fields
    localparam AVMM_USER_WIDTH = to_afu.USER_WIDTH + 1 + ID_WIDTH;

    ofs_plat_avalon_mem_rdwr_if
      #(
        .ADDR_WIDTH(to_afu.ADDR_LINE_IDX_WIDTH),
        .DATA_WIDTH(to_afu.DATA_WIDTH_),
        .MASKED_SYMBOL_WIDTH(to_afu.MASKED_SYMBOL_WIDTH_),
        .BURST_CNT_WIDTH(to_fiu.BURST_CNT_WIDTH_),
        .USER_WIDTH(AVMM_USER_WIDTH)
        )
      afu_avmm_rdwr_if();

    assign afu_avmm_rdwr_if.clk = afu_mem_if.clk;
    assign afu_avmm_rdwr_if.reset_n = afu_mem_if.reset_n;
    assign afu_avmm_rdwr_if.instance_number = afu_mem_if.instance_number;

    // synthesis translate_off
    initial
    begin
        if (afu_avmm_rdwr_if.DATA_WIDTH_ > to_fiu.DATA_WIDTH_)
        begin
            $fatal(2, "** ERROR ** %m: AFU memory DATA_WIDTH (%0d) is wider than FIU (%0d)!",
                   afu_avmm_rdwr_if.DATA_WIDTH_, to_fiu.DATA_WIDTH_);
        end
    end
    // synthesis translate_on

    ofs_plat_axi_mem_if_to_avalon_rdwr_if
      #(
        .GEN_RD_RESPONSE_METADATA(1)
        )
      axi_to_avmm_rdwr
       (
        .axi_master(axi_fiu_burst_if),
        .avmm_slave(afu_avmm_rdwr_if)
        );


    //
    // Map Avalon split-bus read/write to straight Avalon slave.
    //
    ofs_plat_avalon_mem_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(to_fiu),
        .USER_WIDTH(1)
        )
        afu_mem_if();

    ofs_plat_avalon_mem_rdwr_if_to_mem_if
      #(
        .LOCAL_WR_RESPONSE(1)
        )
      avmm_rdwr_to_avmm
       (
        .mem_master(afu_avmm_rdwr_if),
        .mem_slave(afu_mem_if)
        );


    //
    // Clock crossing between AFU and FIU?
    //
    generate
        if (ADD_CLOCK_CROSSING == 0)
        begin : nc
            //
            // No clock crossing, maybe register stages.
            //
            ofs_plat_avalon_mem_if_reg_slave_clk
              #(
                .N_REG_STAGES(NUM_TIMING_REG_STAGES)
                )
              mem_pipe
               (
                .mem_master(afu_mem_if),
                .mem_slave(to_fiu)
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
                .mem_master(afu_mem_if),
                .mem_slave(mem_cross_if)
                );

            // Generate a local reset for timing. This isn't actually a clock
            // crossing reset. We use it because it relaxes the timing on the
            // entire local memory domain here. Waitrequest will be asserted
            // during this reset, so the delay is safe.
            ofs_plat_prim_clock_crossing_reset uClk_usr_reset
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
                .mem_master(mem_cross_if),
                .mem_slave(fiu_reg_if)
                );

            //
            // Register stages for timing at the FIU edge.
            //
            ofs_plat_avalon_mem_if_reg_slave_clk
              #(
                .N_REG_STAGES(NUM_TIMING_REG_STAGES)
                )
              fiu_reg
               (
                .mem_master(fiu_reg_if),
                .mem_slave(to_fiu)
                );
        end
    endgenerate

endmodule // ofs_plat_local_mem_@group@_as_avalon_mem
