//
// Copyright (c) 2019, Intel Corporation
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
// Export an Avalon interface to an AFU, given an FIU interface that is
// already the same interface. The module here offers clock crossing and
// extra register stages.
//
// MMIO is not implemented through native Avalon interfaces.
//

`include "ofs_plat_if.vh"

//
// Host memory as Avalon (no MMIO).
//
module ofs_plat_host_chan_xGROUPx_as_avalon_mem
  #(
    // When non-zero, add a clock crossing to move the AFU
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Size of the read response buffer instantiated when a clock crossing
    // as required.
    parameter MAX_ACTIVE_RD_LINES = 512,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0
    )
   (
    ofs_plat_avalon_mem_if.to_slave to_fiu,

    ofs_plat_avalon_mem_if.to_master_clk host_mem_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    localparam FIU_BURST_CNT_WIDTH = to_fiu.BURST_CNT_WIDTH_;

    // ====================================================================
    //
    // First stage: the AFU's burst counter may be a different size than
    // the FIU's counter. If the AFU counter is larger then map AFU bursts
    // to FIU-sized chunks.
    //
    // ====================================================================

    ofs_plat_avalon_mem_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(host_mem_to_afu)
        )
      afu_burst_if();

    generate
        if (host_mem_to_afu.BURST_CNT_WIDTH_ <= to_fiu.BURST_CNT_WIDTH_)
        begin : nb
            // AFU's burst count is no larger than the FIU's. Just wire
            // the connection to the next stage.
            ofs_plat_avalon_mem_if_connect_slave_clk conn
               (
                .mem_slave(to_fiu),
                .mem_master(afu_burst_if)
                );
        end
        else
        begin : b
            //
            // AFU bursts counts may be too large for the FIU. Map large
            // requests to smaller requests.
            //

            // First add a timing register stage to the FIU side.
            ofs_plat_avalon_mem_if
              #(
                `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(to_fiu)
                )
              fiu_reg_if();

            localparam NUM_BURST_REG_STAGES =
                (`OFS_PLAT_PARAM_HOST_CHAN_XGROUPX_SUGGESTED_TIMING_REG_STAGES > 0) ?
                    `OFS_PLAT_PARAM_HOST_CHAN_XGROUPX_SUGGESTED_TIMING_REG_STAGES : 1;

            ofs_plat_avalon_mem_if_reg_slave_clk
              #(
                .N_REG_STAGES(NUM_BURST_REG_STAGES)
                )
              conn
               (
                .mem_slave(to_fiu),
                .mem_master(fiu_reg_if)
                );

            //
            // Squash extra write responses from smaller slave bursts. Only the
            // final response will reach the AFU.
            //
            ofs_plat_avalon_mem_if
              #(
                `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(to_fiu)
                )
              fiu_burst_if();

            assign fiu_burst_if.clk = to_fiu.clk;
            assign fiu_burst_if.reset_n = to_fiu.reset_n;
            assign fiu_burst_if.instance_number = to_fiu.instance_number;

            logic fiu_burst_if_sop;
            logic wr_slave_burst_expects_response;

            // Track SOP write beats (there is one response per SOP)
            ofs_plat_prim_burstcount_sop_tracker
              #(
                .BURST_CNT_WIDTH(FIU_BURST_CNT_WIDTH)
                )
              sop_tracker
               (
                .clk(to_fiu.clk),
                .reset_n(to_fiu.reset_n),
                .flit_valid(fiu_burst_if.write && !fiu_burst_if.waitrequest),
                .burstcount(fiu_burst_if.burstcount),
                .sop(fiu_burst_if_sop),
                .eop()
                );

            // One bit FIFO tracker indicating whether a write response should be
            // forwarded to the AFU.
            logic wr_resp_fifo_notFull;
            logic wr_resp_expected;

            ofs_plat_prim_fifo_lutram
              #(
                .N_DATA_BITS(1),
                .N_ENTRIES(128),
                .REGISTER_OUTPUT(1)
                )
              wr_resp_fifo
               (
                .clk(to_fiu.clk),
                .reset_n(to_fiu.reset_n),
                .enq_data(wr_slave_burst_expects_response),
                .enq_en(fiu_burst_if_sop && fiu_burst_if.write &&
                        !fiu_burst_if.waitrequest),
                .notFull(wr_resp_fifo_notFull),
                .almostFull(),
                .first(wr_resp_expected),
                .deq_en(fiu_reg_if.writeresponsevalid),
                .notEmpty()
                );

            always_comb
            begin
                `OFS_PLAT_AVALON_MEM_IF_FROM_MASTER_TO_SLAVE_COMB(fiu_reg_if,
                                                                  fiu_burst_if);

                fiu_burst_if.waitrequest = fiu_reg_if.waitrequest;
                fiu_burst_if.readdatavalid = fiu_reg_if.readdatavalid;
                fiu_burst_if.readdata = fiu_reg_if.readdata;
                fiu_burst_if.response = fiu_reg_if.response;
                fiu_burst_if.writeresponsevalid = fiu_reg_if.writeresponsevalid &&
                                                  wr_resp_expected;
                fiu_burst_if.writeresponse = fiu_reg_if.writeresponse;
            end

            //
            // Map from master bursts to slave bursts
            //
            assign afu_burst_if.clk = to_fiu.clk;
            assign afu_burst_if.reset_n = to_fiu.reset_n;
            assign afu_burst_if.instance_number = to_fiu.instance_number;

            ofs_plat_avalon_mem_if_map_bursts burst
               (
                .mem_slave(fiu_burst_if),
                .mem_master(afu_burst_if),
                .wr_slave_burst_expects_response
                );
        end
    endgenerate


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
            if (`OFS_PLAT_PARAM_HOST_CHAN_XGROUPX_SUGGESTED_TIMING_REG_STAGES > n_stages)
            begin
                n_stages = `OFS_PLAT_PARAM_HOST_CHAN_XGROUPX_SUGGESTED_TIMING_REG_STAGES;
            end
        end

        return n_stages;
    endfunction

    localparam NUM_TIMING_REG_STAGES = numTimingRegStages();

    ofs_plat_avalon_mem_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(host_mem_to_afu)
        )
        afu_mem_if();

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
                .mem_slave(afu_burst_if),
                .mem_master(afu_mem_if)
                );
        end
        else
        begin : ofs_plat_clock_crossing
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
                `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(host_mem_to_afu),
                .WAIT_REQUEST_ALLOWANCE(NUM_WAITREQUEST_STAGES)
                )
                mem_cross();

            assign mem_cross.clk = afu_clk;
            assign mem_cross.reset_n = afu_reset_n;
            assign mem_cross.instance_number = to_fiu.instance_number;

            // synthesis translate_off
            always_ff @(negedge afu_clk)
            begin
                if (afu_reset_n === 1'bx)
                begin
                    $fatal(2, "** ERROR ** %m: afu_reset_n port is uninitialized!");
                end
            end
            // synthesis translate_on

            ofs_plat_avalon_mem_if_async_shim
              #(
                .COMMAND_FIFO_DEPTH(8 + NUM_ALMFULL_SLOTS),
                .RESPONSE_FIFO_DEPTH(MAX_ACTIVE_RD_LINES),
                .COMMAND_ALMFULL_THRESHOLD(NUM_ALMFULL_SLOTS)
                )
              cross_clk
               (
                .mem_slave(afu_burst_if),
                .mem_master(mem_cross)
                );

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
                .mem_slave(mem_cross),
                .mem_master(afu_mem_if)
                );

            assign afu_mem_if.clk = mem_cross.clk;
            assign afu_mem_if.reset_n = mem_cross.reset_n;
            // Debugging signal
            assign afu_mem_if.instance_number = mem_cross.instance_number;
        end
    endgenerate

    // Make the final connection to the host_mem_to_afu instance, including
    // passing the clock.
    ofs_plat_avalon_mem_if_connect_slave_clk conn_to_afu
       (
        .mem_slave(afu_mem_if),
        .mem_master(host_mem_to_afu)
        );

endmodule // ofs_plat_host_chan_xGROUPx_as_avalon_mem
