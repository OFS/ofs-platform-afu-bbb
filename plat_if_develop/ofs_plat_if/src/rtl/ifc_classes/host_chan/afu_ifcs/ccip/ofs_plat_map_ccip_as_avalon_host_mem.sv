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
// Map CCI-P host memory traffic to an Avalon channel. The incoming CCI-P
// responses are out of order, so must be sorted. The same buffer is
// used for clock crossing, if needed, and sorting.
//
module ofs_plat_map_ccip_as_avalon_host_mem
  #(
    // When non-zero, add a clock crossing to move the Avalon
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Sizes of the response buffers in the ROB and clock crossing.
    parameter MAX_ACTIVE_RD_LINES = 256,
    parameter MAX_ACTIVE_WR_LINES = 256,

    parameter ADD_TIMING_REG_STAGES = 0
    )
   (
    // CCI-P interface to FIU
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    // Generated Avalon host memory interface
    ofs_plat_avalon_mem_rdwr_if.to_master_clk host_mem_to_afu,

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
    ofs_plat_avalon_mem_rdwr_if
      #(
        `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS(host_mem_to_afu)
        )
      avmm_afu_clk_if();

    assign avmm_afu_clk_if.clk = (ADD_CLOCK_CROSSING == 0) ? clk : afu_clk;
    assign avmm_afu_clk_if.reset_n = (ADD_CLOCK_CROSSING == 0) ? reset_n : afu_reset_n;
    assign avmm_afu_clk_if.instance_number = to_fiu.instance_number;

    // synthesis translate_off
    always_ff @(negedge avmm_afu_clk_if.clk)
    begin
        if (avmm_afu_clk_if.reset_n === 1'bx)
        begin
            $fatal(2, "** ERROR ** %m: avmm_afu_clk_if.reset_n port is uninitialized!");
        end
    end
    // synthesis translate_on

    //
    // Connect the AFU clock and add a register stage for timing next
    // to the burst mapper.
    //
    ofs_plat_avalon_mem_rdwr_if_reg_slave_clk
      #(
        .N_REG_STAGES(ADD_TIMING_REG_STAGES + 1)
        )
      conn_afu_clk
       (
        .mem_master(host_mem_to_afu),
        .mem_slave(avmm_afu_clk_if)
        );


    //
    // The AFU has set the burst count width of host_mem_to_afu to whatever
    // is expected by the AFU. CCI-P requires bursts no larger than 4 lines.
    // The bursts must also be naturally aligned. Transform host_mem_to_afu
    // bursts to legal CCI-P bursts.
    //
    ofs_plat_avalon_mem_rdwr_if
      #(
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN),
        `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_MEM_PARAMS(host_mem_to_afu),
        .BURST_CNT_WIDTH(3),
        // ofs_plat_avalon_mem_rdwr_if_map_bursts records whether write
        // responses are expected on wr_user[0].
        .USER_WIDTH(host_mem_to_afu.USER_WIDTH_ + 1)
        )
      avmm_fiu_burst_if();

    assign avmm_fiu_burst_if.clk = avmm_afu_clk_if.clk;
    assign avmm_fiu_burst_if.reset_n = avmm_afu_clk_if.reset_n;
    assign avmm_fiu_burst_if.instance_number = avmm_afu_clk_if.instance_number;

    ofs_plat_avalon_mem_rdwr_if_map_bursts
      #(
        .NATURAL_ALIGNMENT(1)
        )
      map_bursts
       (
        .mem_master(avmm_afu_clk_if),
        .mem_slave(avmm_fiu_burst_if)
        );


    //
    // Cross to the FIU clock and add register stages. The two are combined
    // because the clock crossing buffer can also be used to simplify the
    // Avalon waitrequest protocol.
    //

    // ofs_plat_avalon_mem_rdwr_if_async_rob records the ROB indices
    // of read and write requests in rd_user and wr_user fields.
    // Size the user fields using whichever index space is larger.
    localparam USER_WIDTH =
        host_mem_to_afu.USER_WIDTH_ + 1 +
        $clog2((MAX_ACTIVE_RD_LINES > MAX_ACTIVE_WR_LINES) ? MAX_ACTIVE_RD_LINES :
                                                             MAX_ACTIVE_WR_LINES);

    ofs_plat_avalon_mem_rdwr_if
      #(
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN),
        `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_MEM_PARAMS(avmm_fiu_burst_if),
        .BURST_CNT_WIDTH(avmm_fiu_burst_if.BURST_CNT_WIDTH_),
        .USER_WIDTH(USER_WIDTH)
        )
      avmm_fiu_clk_if();

    assign avmm_fiu_clk_if.clk = clk;
    assign avmm_fiu_clk_if.reset_n = reset_n;
    assign avmm_fiu_clk_if.instance_number = to_fiu.instance_number;

    ofs_plat_avalon_mem_rdwr_if_async_rob
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .MAX_ACTIVE_RD_LINES(MAX_ACTIVE_RD_LINES),
        .MAX_ACTIVE_WR_LINES(MAX_ACTIVE_WR_LINES)
        )
      rob
       (
        .mem_master(avmm_fiu_burst_if),
        .mem_slave(avmm_fiu_clk_if)
        );


    // Map almost full to Avalon waitrequest
    always_ff @(posedge clk)
    begin
        avmm_fiu_clk_if.rd_waitrequest <= sRx.c0TxAlmFull;
        avmm_fiu_clk_if.wr_waitrequest <= sRx.c1TxAlmFull;
    end

    //
    // Host memory reads
    //
    always_ff @(posedge clk)
    begin
        to_fiu.sTx.c0.valid <= avmm_fiu_clk_if.rd_read && ! avmm_fiu_clk_if.rd_waitrequest;

        to_fiu.sTx.c0.hdr <= t_ccip_c0_ReqMemHdr'(0);
        to_fiu.sTx.c0.hdr.mdata <= t_ccip_mdata'(avmm_fiu_clk_if.rd_user);
        to_fiu.sTx.c0.hdr.address <= avmm_fiu_clk_if.rd_address;
        to_fiu.sTx.c0.hdr.req_type <= eREQ_RDLINE_I;
        to_fiu.sTx.c0.hdr.cl_len <= t_ccip_clLen'(avmm_fiu_clk_if.rd_burstcount - 3'b1);

        if (!reset_n)
        begin
            to_fiu.sTx.c0.valid <= 1'b0;
        end
    end

    // CCI-P responses are already sorted. Just forward them to Avalon.
    always_ff @(posedge clk)
    begin
        avmm_fiu_clk_if.rd_readdatavalid <= ccip_c0Rx_isReadRsp(sRx.c0);
        avmm_fiu_clk_if.rd_readdata <= sRx.c0.data;
        // Index of the ROB entry
        avmm_fiu_clk_if.rd_readresponseuser <= USER_WIDTH'(sRx.c0.hdr.mdata + sRx.c0.hdr.cl_num);

        if (!reset_n)
        begin
            avmm_fiu_clk_if.rd_readdatavalid <= 1'b0;
        end
    end

    assign avmm_fiu_clk_if.rd_response = 2'b0;

    //
    // Host memory writes
    //
    logic wr_beat_valid;
    assign wr_beat_valid = avmm_fiu_clk_if.wr_write && ! avmm_fiu_clk_if.wr_waitrequest;

    logic wr_sop;
    t_ccip_clLen wr_cl_len;
    t_ccip_clNum wr_cl_num;
    t_ccip_clNum wr_cl_addr;

    // Is the current incoming write line the end of a packet? It is if either
    // starting a new single-line packet or all lines of a multi-line
    // package have now arrived.
    logic wr_eop;
    assign wr_eop = (wr_sop && (avmm_fiu_clk_if.wr_burstcount == 3'b1)) ||
                    (!wr_sop && (wr_cl_num == t_ccip_clNum'(wr_cl_len)));

    always_ff @(posedge clk)
    begin
        to_fiu.sTx.c1.valid <= wr_beat_valid;
        to_fiu.sTx.c1.data <= avmm_fiu_clk_if.wr_writedata;

        if (wr_sop)
        begin
            to_fiu.sTx.c1.hdr <= t_ccip_c1_ReqMemHdr'(0);
            to_fiu.sTx.c1.hdr.mdata <= t_ccip_mdata'(avmm_fiu_clk_if.wr_user);

            if (! avmm_fiu_clk_if.wr_function)
            begin
                // Normal write
                to_fiu.sTx.c1.hdr.address <= avmm_fiu_clk_if.wr_address;
                to_fiu.sTx.c1.hdr.req_type <= eREQ_WRLINE_I;
                to_fiu.sTx.c1.hdr.cl_len <= t_ccip_clLen'(avmm_fiu_clk_if.wr_burstcount - 3'b1);
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
                wr_cl_len <= t_ccip_clLen'(avmm_fiu_clk_if.wr_burstcount - 3'b1);
                wr_cl_addr <= t_ccip_clNum'(avmm_fiu_clk_if.wr_address);
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

    always_ff @(posedge clk)
    begin
        avmm_fiu_clk_if.wr_writeresponsevalid <=
            (ccip_c1Rx_isWriteRsp(sRx.c1) || ccip_c1Rx_isWriteFenceRsp(sRx.c1));

        // Index of the ROB entry. Responses are already guaranteed packed by
        // the PIM's CCI-P shim.
        avmm_fiu_clk_if.wr_writeresponseuser <= USER_WIDTH'(sRx.c1.hdr.mdata);

        if (!reset_n)
        begin
            avmm_fiu_clk_if.wr_writeresponsevalid <= 1'b0;
        end
    end

    assign avmm_fiu_clk_if.wr_response = 2'b0;

endmodule // ofs_plat_map_ccip_as_avalon_host_mem
