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

    // Sizes of the response buffers in the ROB and clock crossing.
    parameter MAX_ACTIVE_RD_LINES = `OFS_PLAT_PARAM_HOST_CHAN_XGROUPX_MAX_BW_ACTIVE_LINES_RD,
    parameter MAX_ACTIVE_WR_LINES = `OFS_PLAT_PARAM_HOST_CHAN_XGROUPX_MAX_BW_ACTIVE_LINES_WR,

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
    localparam FIU_USER_WIDTH = to_fiu.USER_WIDTH_;

`ifdef OFS_PLAT_PARAM_HOST_CHAN_XGROUPX_OUT_OF_ORDER
    localparam OUT_OF_ORDER = `OFS_PLAT_PARAM_HOST_CHAN_XGROUPX_OUT_OF_ORDER;
`else
    localparam OUT_OF_ORDER = 0;
`endif

    // Does the FIU port return responses out of order? If so, the user
    // port must be available as a tag.
    // synthesis translate_off
    initial
    begin
        if (OUT_OF_ORDER)
        begin
            assert (FIU_USER_WIDTH > 1) else
                $fatal(2, " ** ERROR ** %m: Port is out of order but USER_WIDTH is too small!");

            assert (FIU_BURST_CNT_WIDTH == 1) else
                $fatal(2, " ** ERROR ** %m: Port is out of order but max. burst count is not 1!");
        end
    end
    // synthesis translate_on

    // ====================================================================
    //
    //  Add register stages at the FIU edge.
    //
    // ====================================================================

    //
    // How many register stages should be inserted for timing?
    //
    function automatic int numTimingRegStages(int at_fiu_edge);
        int n_stages;

        if ((at_fiu_edge != 0) && ((OUT_OF_ORDER + ADD_CLOCK_CROSSING) != 0))
        begin
            // At the edge and a clock crossing will be added. Add just
            // the minimum number of stages. The rest will be added between
            // the clock crossing and the AFU.
            n_stages = `OFS_PLAT_PARAM_HOST_CHAN_XGROUPX_SUGGESTED_TIMING_REG_STAGES + 1;
        end
        else
        begin
            // Were timing registers requested?
            n_stages = ADD_TIMING_REG_STAGES + 1;

            // Override the register request if a clock crossing is being
            // inserted here.
            if (`OFS_PLAT_PARAM_HOST_CHAN_XGROUPX_SUGGESTED_TIMING_REG_STAGES > n_stages)
            begin
                n_stages = `OFS_PLAT_PARAM_HOST_CHAN_XGROUPX_SUGGESTED_TIMING_REG_STAGES;
            end
        end

        return n_stages;
    endfunction

    ofs_plat_avalon_mem_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(to_fiu),
        .USER_WIDTH(FIU_USER_WIDTH)
        )
        fiu_reg_if();

    ofs_plat_avalon_mem_if_reg_slave_clk
      #(
        .N_REG_STAGES(numTimingRegStages(1))
        )
      mem_pipe
       (
        .mem_slave(to_fiu),
        .mem_master(fiu_reg_if)
        );

    ofs_plat_avalon_mem_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(to_fiu)
        )
        afu_clk_if();


    // ====================================================================
    //
    //  Manage clock crossing to AFU.
    //
    // ====================================================================

    generate
        if ((OUT_OF_ORDER + ADD_CLOCK_CROSSING) == 0)
        begin : nc
            //
            // Port is ordered and no clock crossing is requested.
            //
            ofs_plat_avalon_mem_if_connect_slave_clk fiu_conn
               (
                .mem_slave(fiu_reg_if),
                .mem_master(afu_clk_if)
                );
        end
        else
        begin : cc
            localparam NUM_TIMING_REG_STAGES = numTimingRegStages(0);

            //
            // Cross to the specified clock and/or add a reorder buffer
            //
            ofs_plat_avalon_mem_if
              #(
                `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(to_fiu)
                )
                mem_cross();

            assign mem_cross.clk = (ADD_CLOCK_CROSSING ? afu_clk : to_fiu.clk);
            assign mem_cross.reset_n = (ADD_CLOCK_CROSSING ? afu_reset_n : to_fiu.reset_n);
            assign mem_cross.instance_number = to_fiu.instance_number;

            // synthesis translate_off
            always_ff @(negedge afu_clk)
            begin
                if ((ADD_CLOCK_CROSSING != 0) && (afu_reset_n === 1'bx))
                begin
                    $fatal(2, "** ERROR ** %m: afu_reset_n port is uninitialized!");
                end
            end
            // synthesis translate_on

            if (OUT_OF_ORDER)
            begin
                // At least a ROB and maybe a clock crossing. The user field
                // in the slave interface is used for the reordering tag.
                ofs_plat_avalon_mem_if_async_rob
                  #(
                    .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
                    .MAX_ACTIVE_RD_LINES(MAX_ACTIVE_RD_LINES),
                    .MAX_ACTIVE_WR_LINES(MAX_ACTIVE_WR_LINES)
                    )
                  rob
                   (
                    .mem_slave(fiu_reg_if),
                    .mem_master(mem_cross)
                    );
            end
            else
            begin
                // Just a clock crossing. No ROB required.
                ofs_plat_avalon_mem_if_async_shim
                  #(
                    .COMMAND_FIFO_DEPTH(8),
                    .RESPONSE_FIFO_DEPTH(MAX_ACTIVE_RD_LINES)
                    )
                  cross_clk
                   (
                    .mem_slave(fiu_reg_if),
                    .mem_master(mem_cross)
                    );
            end

            ofs_plat_avalon_mem_if_reg
              #(
                .N_REG_STAGES(NUM_TIMING_REG_STAGES)
                )
              mem_pipe
               (
                .mem_slave(mem_cross),
                .mem_master(afu_clk_if)
                );

            assign afu_clk_if.clk = mem_cross.clk;
            assign afu_clk_if.reset_n = mem_cross.reset_n;
            // Debugging signal
            assign afu_clk_if.instance_number = mem_cross.instance_number;
        end
    endgenerate


    // ====================================================================
    //
    //  The AFU's burst counter may be a different size than the FIU's
    //  counter. If the AFU counter is larger then map AFU bursts to
    //  FIU-sized chunks.
    //
    // ====================================================================

    generate
        if (host_mem_to_afu.BURST_CNT_WIDTH_ <= afu_clk_if.BURST_CNT_WIDTH_)
        begin : nb
            // AFU's burst count is no larger than the FIU's. Just wire
            // the connection to the next stage.
            ofs_plat_avalon_mem_if_connect_slave_clk conn
               (
                .mem_slave(afu_clk_if),
                .mem_master(host_mem_to_afu)
                );
        end
        else
        begin : b
            //
            // AFU bursts counts may be too large for the FIU. Map large
            // requests to smaller requests.
            //
            ofs_plat_avalon_mem_if
              #(
                `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(to_fiu),
                // user field bit 0 used to track required write responses
                .USER_WIDTH(1)
                )
              fiu_burst_if();

            assign fiu_burst_if.clk = afu_clk_if.clk;
            assign fiu_burst_if.reset_n = afu_clk_if.reset_n;
            assign fiu_burst_if.instance_number = afu_clk_if.instance_number;

            logic fiu_burst_if_sop;

            // Track SOP write beats (there is one response per SOP)
            ofs_plat_prim_burstcount1_sop_tracker
              #(
                .BURST_CNT_WIDTH(FIU_BURST_CNT_WIDTH)
                )
              sop_tracker
               (
                .clk(fiu_burst_if.clk),
                .reset_n(fiu_burst_if.reset_n),
                .flit_valid(fiu_burst_if.write && !fiu_burst_if.waitrequest),
                .burstcount(fiu_burst_if.burstcount),
                .sop(fiu_burst_if_sop),
                .eop()
                );

            // One bit FIFO tracker indicating whether a write response should be
            // forwarded to the AFU. The burst mapper expects this in user[0].
            logic wr_resp_fifo_notFull;
            logic wr_resp_expected;

            ofs_plat_prim_fifo_lutram
              #(
                .N_DATA_BITS(1),
                .N_ENTRIES(MAX_ACTIVE_WR_LINES),
                .REGISTER_OUTPUT(1)
                )
              wr_resp_fifo
               (
                .clk(fiu_burst_if.clk),
                .reset_n(fiu_burst_if.reset_n),
                .enq_data(fiu_burst_if.user[0]),
                .enq_en(fiu_burst_if_sop && fiu_burst_if.write &&
                        !fiu_burst_if.waitrequest),
                .notFull(wr_resp_fifo_notFull),
                .almostFull(),
                .first(wr_resp_expected),
                .deq_en(fiu_burst_if.writeresponsevalid),
                .notEmpty()
                );

            always_comb
            begin
                `OFS_PLAT_AVALON_MEM_IF_FROM_MASTER_TO_SLAVE_COMB(afu_clk_if,
                                                                  fiu_burst_if);
                `OFS_PLAT_AVALON_MEM_IF_FROM_SLAVE_TO_MASTER_COMB(fiu_burst_if,
                                                                  afu_clk_if);

                afu_clk_if.read = fiu_burst_if.read && wr_resp_fifo_notFull;
                afu_clk_if.write = fiu_burst_if.write && wr_resp_fifo_notFull;

                fiu_burst_if.waitrequest = afu_clk_if.waitrequest || !wr_resp_fifo_notFull;
                fiu_burst_if.writeresponseuser[0] = wr_resp_expected;
            end

            //
            // Map from master bursts to slave bursts
            //
            ofs_plat_avalon_mem_if
              #(
                `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(host_mem_to_afu)
                )
              afu_burst_if();

            assign afu_burst_if.clk = fiu_burst_if.clk;
            assign afu_burst_if.reset_n = fiu_burst_if.reset_n;
            assign afu_burst_if.instance_number = fiu_burst_if.instance_number;

            ofs_plat_avalon_mem_if_map_bursts burst
               (
                .mem_slave(fiu_burst_if),
                .mem_master(afu_burst_if)
                );

            ofs_plat_avalon_mem_if_reg_slave_clk afu_conn
               (
                .mem_slave(afu_burst_if),
                .mem_master(host_mem_to_afu)
                );
        end
    endgenerate

endmodule // ofs_plat_host_chan_xGROUPx_as_avalon_mem
