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

`include "ofs_plat_if.vh"

//
// Map CCI-P host memory traffic to an AXI channel.
//
module ofs_plat_map_ccip_as_axi_host_mem
  #(
    // When non-zero, add a clock crossing to move the AXI
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Size of the read response buffer instantiated when a clock crossing
    // as required.
    parameter MAX_ACTIVE_RD_LINES = 256,

    parameter ADD_TIMING_REG_STAGES = 0
    )
   (
    // CCI-P interface to FIU
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    // Generated AXI host memory interface
    ofs_plat_axi_mem_if.to_master_clk host_mem_to_afu,

    // Used for AFU clock/reset_n when ADD_CLOCK_CROSSING is nonzero
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    import ofs_plat_ccip_if_funcs_pkg::*;

    logic clk;
    assign clk = to_fiu.clk;

    logic reset_n;
    assign reset_n = to_fiu.reset_n;

    t_if_ccip_Rx sRx;
    assign sRx = to_fiu.sRx;

    // Tie off sTx.c2. MMIO should have been split off before passing to_fiu
    // to this module.
    assign to_fiu.sTx.c2 = t_if_ccip_c2_Tx'(0);

    // ====================================================================
    //
    //  Begin with the AFU connection (host_mem_to_afu) and work down
    //  toward the FIU.
    //
    // ====================================================================

    //
    // Bind the proper clock to the AFU interface. If there is no clock
    // crossing requested then it's just the FIU CCI-P clock.
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(host_mem_to_afu)
        )
      axi_afu_clk_if();

    assign axi_afu_clk_if.clk = (ADD_CLOCK_CROSSING == 0) ? clk : afu_clk;
    assign axi_afu_clk_if.reset_n = (ADD_CLOCK_CROSSING == 0) ? reset_n : afu_reset_n;
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

    ofs_plat_axi_mem_if_connect_slave_clk
      conn_afu_clk
       (
        .mem_master(host_mem_to_afu),
        .mem_slave(axi_afu_clk_if)
        );

    //
    // Cross to the FIU clock and add register stages. The two are combined
    // because the clock crossing buffer can also be used to simplify the
    // AXI waitrequest protocol.
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(host_mem_to_afu)
        )
      axi_fiu_clk_if();

    assign axi_fiu_clk_if.clk = clk;
    assign axi_fiu_clk_if.reset_n = reset_n;
    assign axi_fiu_clk_if.instance_number = to_fiu.instance_number;

`ifdef FOOBAR
    generate
        if (ADD_CLOCK_CROSSING == 0)
        begin : nc
            //
            // No clock crossing buffer. Must use normal AXI waitrequest
            // protocol.
            //
`endif
            ofs_plat_axi_mem_if_reg
              #(
                .N_REG_STAGES(ADD_TIMING_REG_STAGES)
                )
              conn_same_clk
               (
                .mem_master(axi_afu_clk_if),
                .mem_slave(axi_fiu_clk_if)
                );
`ifdef FOOBAR
        end
        else
        begin : cc
            //
            // We can reserve some space in the clock crossing block RAM for
            // pipelined requests, allowing us to treat waitrequest more like
            // an almost full protocol.
            //

            // We assume that a single waitrequest signal can propagate faster
            // than the entire bus, so limit the number of stages.
            localparam NUM_WAITREQUEST_STAGES =
                // If pipeline is 4 stages or fewer then use the pipeline depth.
                (ADD_TIMING_REG_STAGES <= 4 ? ADD_TIMING_REG_STAGES :
                    // Up to depth 16 pipelines, use 4 waitrequest stages.
                    // Beyond 16 stages, set the waitrequest depth to 1/4 the
                    // base pipeline depth.
                    (ADD_TIMING_REG_STAGES <= 16 ? 4 : (ADD_TIMING_REG_STAGES >> 2)));

            ofs_plat_axi_mem_if
              #(
                `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(host_mem_to_afu),
                .WAIT_REQUEST_ALLOWANCE(NUM_WAITREQUEST_STAGES)
                )
              axi_reg_if();

            assign axi_reg_if.clk = afu_clk;
            assign axi_reg_if.reset_n = afu_reset_n;
            assign axi_reg_if.instance_number = to_fiu.instance_number;

            ofs_plat_axi_mem_if_reg_simple
              #(
                .N_REG_STAGES(ADD_TIMING_REG_STAGES),
                .N_WAITREQUEST_STAGES(NUM_WAITREQUEST_STAGES)
                )
              conn_reg
               (
                .mem_master(axi_afu_clk_if),
                .mem_slave(axi_reg_if)
                );

            //
            // Now the actual clock crossing. First we must calculate the number
            // of extra slots required due to timing register stages.
            //

            // A few extra stages to avoid off-by-one errors. There is plenty of
            // space in the FIFO, so this has no performance consequences.
            localparam NUM_EXTRA_STAGES = (ADD_TIMING_REG_STAGES != 0) ? 4 : 0;

            // Set the almost full threshold to satisfy the buffering pipeline depth
            // plus the depth of the waitrequest pipeline plus a little extra to
            // avoid having to worry about off-by-one errors.
            localparam NUM_ALMFULL_SLOTS = ADD_TIMING_REG_STAGES +
                                           NUM_WAITREQUEST_STAGES +
                                           NUM_EXTRA_STAGES;

            ofs_plat_axi_mem_if_async_shim
              #(
                .RD_COMMAND_FIFO_DEPTH(8 + NUM_ALMFULL_SLOTS),
                .RD_RESPONSE_FIFO_DEPTH(MAX_ACTIVE_RD_LINES),
                .WR_COMMAND_FIFO_DEPTH(8 + NUM_ALMFULL_SLOTS),
                .COMMAND_ALMFULL_THRESHOLD(NUM_ALMFULL_SLOTS)
                )
              cross_clk
               (
                .mem_master(axi_reg_if),
                .mem_slave(axi_fiu_clk_if)
                );
        end
    endgenerate
`endif

    //
    // Add a register stage for timing next to the burst mapper.
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(host_mem_to_afu)
        )
      axi_fiu_reg_if();

    assign axi_fiu_reg_if.clk = clk;
    assign axi_fiu_reg_if.reset_n = reset_n;
    assign axi_fiu_reg_if.instance_number = to_fiu.instance_number;

    ofs_plat_axi_mem_if_reg
      f_reg
       (
        .mem_master(axi_fiu_clk_if),
        .mem_slave(axi_fiu_reg_if)
        );

    //
    // The AFU has set the burst count width of host_mem_to_afu to whatever
    // is expected by the AFU. CCI-P requires bursts no larger than 4 lines.
    // The bursts must also be naturally aligned. Transform host_mem_to_afu
    // bursts to legal CCI-P bursts.
    //
    ofs_plat_axi_mem_if
      #(
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN),
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_MEM_PARAMS(host_mem_to_afu),
        .BURST_CNT_WIDTH(3)
        )
      axi_fiu_burst_if();

    assign axi_fiu_burst_if.clk = clk;
    assign axi_fiu_burst_if.reset_n = reset_n;
    assign axi_fiu_burst_if.instance_number = to_fiu.instance_number;

    logic fiu_burst_expects_response;
    ofs_plat_axi_mem_if_map_bursts
      #(
        .NATURAL_ALIGNMENT(1)
        )
      map_bursts
       (
        .mem_master(axi_fiu_reg_if),
        .mem_slave(axi_fiu_burst_if),

        // The AFU interface requires one response per AFU-sized burst.
        // When mapping a single AFU burst to multiple FIU write bursts
        // only the last FIU write burst should generate a response to
        // the AFU.
        .wr_slave_burst_expects_response(fiu_burst_expects_response)
        );


    // ====================================================================
    //
    //  axi_fiu_burst_if is in the FIU's CCI-P clock domain and the
    //  bursts are legal CCI-P sizes and address alignment. A 1:1 mapping
    //  of AXI to CCI-P messages is now possible.
    //
    // ====================================================================

    // Map almost full to AXI waitrequest
    always_ff @(posedge clk)
    begin
        axi_fiu_burst_if.arready <= !sRx.c0TxAlmFull;
        axi_fiu_burst_if.awready <= !sRx.c1TxAlmFull;
        axi_fiu_burst_if.wready <= !sRx.c1TxAlmFull;
    end

    assign to_fiu.sTx.c0 = '0;
    assign to_fiu.sTx.c1 = '0;
    assign axi_fiu_burst_if.rvalid = 1'b0;
    assign axi_fiu_burst_if.bvalid = 1'b0;
`ifdef FOOBAR
    //
    // Host memory reads
    //
    always_ff @(posedge clk)
    begin
        to_fiu.sTx.c0.valid <= axi_fiu_burst_if.rd_read && ! axi_fiu_burst_if.rd_waitrequest;

        to_fiu.sTx.c0.hdr <= t_ccip_c0_ReqMemHdr'(0);
        to_fiu.sTx.c0.hdr.address <= axi_fiu_burst_if.rd_address;
        to_fiu.sTx.c0.hdr.req_type <= eREQ_RDLINE_I;
        to_fiu.sTx.c0.hdr.cl_len <= t_ccip_clLen'(axi_fiu_burst_if.rd_burstcount - 3'b1);

        if (!reset_n)
        begin
            to_fiu.sTx.c0.valid <= 1'b0;
        end
    end

    // CCI-P responses are already sorted. Just forward them to AXI.
    always_ff @(posedge clk)
    begin
        axi_fiu_burst_if.rd_readdatavalid <= ccip_c0Rx_isReadRsp(sRx.c0);
        axi_fiu_burst_if.rd_readdata <= sRx.c0.data;

        if (!reset_n)
        begin
            axi_fiu_burst_if.rd_readdatavalid <= 1'b0;
        end
    end

    assign axi_fiu_burst_if.rd_response = 2'b0;

    //
    // Host memory writes
    //
    logic wr_beat_valid;
    assign wr_beat_valid = axi_fiu_burst_if.wr_write && ! axi_fiu_burst_if.wr_waitrequest;

    logic wr_sop;
    t_ccip_clLen wr_cl_len;
    t_ccip_clNum wr_cl_num;
    t_ccip_clNum wr_cl_addr;

    // Is the current incoming write line the end of a packet? It is if either
    // starting a new single-line packet or all lines of a multi-line
    // package have now arrived.
    logic wr_eop;
    assign wr_eop = (wr_sop && (axi_fiu_burst_if.wr_burstcount == 3'b1)) ||
                    (!wr_sop && (wr_cl_num == t_ccip_clNum'(wr_cl_len)));

    always_ff @(posedge clk)
    begin
        to_fiu.sTx.c1.valid <= wr_beat_valid;
        to_fiu.sTx.c1.data <= axi_fiu_burst_if.wr_writedata;

        if (wr_sop)
        begin
            to_fiu.sTx.c1.hdr <= t_ccip_c1_ReqMemHdr'(0);
            to_fiu.sTx.c1.hdr.mdata[0] <= fiu_burst_expects_response;

            if (! axi_fiu_burst_if.wr_function)
            begin
                // Normal write
                to_fiu.sTx.c1.hdr.address <= axi_fiu_burst_if.wr_address;
                to_fiu.sTx.c1.hdr.req_type <= eREQ_WRLINE_I;
                to_fiu.sTx.c1.hdr.cl_len <= t_ccip_clLen'(axi_fiu_burst_if.wr_burstcount - 3'b1);
                to_fiu.sTx.c1.hdr.sop <= 1'b1;
            end
            else
            begin
                // Write fence. req_type and mdata are in the same places in the
                // header as a normal write.
                to_fiu.sTx.c1.hdr.req_type <= eREQ_WRFENCE;
            end
        end
        else
        begin
            to_fiu.sTx.c1.hdr.address[1:0] <= wr_cl_addr | wr_cl_num;
            to_fiu.sTx.c1.hdr.sop <= 1'b0;
        end

        // Update multi-line state
        if (wr_beat_valid)
        begin
            if (wr_sop)
            begin
                wr_cl_len <= t_ccip_clLen'(axi_fiu_burst_if.wr_burstcount - 3'b1);
                wr_cl_addr <= t_ccip_clNum'(axi_fiu_burst_if.wr_address);
            end

            if (wr_eop)
            begin
                wr_sop <= 1'b1;
                wr_cl_num <= t_ccip_clNum'(0);
            end
            else
            begin
                wr_sop <= 1'b0;
                wr_cl_num <= wr_cl_num + t_ccip_clNum'(1);
            end
        end

        if (!reset_n)
        begin
            to_fiu.sTx.c1.valid <= 1'b0;
            wr_sop <= 1'b1;
            wr_cl_len <= eCL_LEN_1;
            wr_cl_num <= t_ccip_clNum'(0);
        end
    end

    // CCI-P write responses are already packed and sorted. Just forward them to
    // AXI. Bit 0 of mdata records whether the write expects a response.
    always_ff @(posedge clk)
    begin
        axi_fiu_burst_if.wr_writeresponsevalid <=
            (ccip_c1Rx_isWriteRsp(sRx.c1) || ccip_c1Rx_isWriteFenceRsp(sRx.c1)) &&
            sRx.c1.hdr.mdata[0];

        if (!reset_n)
        begin
            axi_fiu_burst_if.wr_writeresponsevalid <= 1'b0;
        end
    end

    assign axi_fiu_burst_if.wr_response = 2'b0;
`endif

endmodule // ofs_plat_map_ccip_as_axi_host_mem
