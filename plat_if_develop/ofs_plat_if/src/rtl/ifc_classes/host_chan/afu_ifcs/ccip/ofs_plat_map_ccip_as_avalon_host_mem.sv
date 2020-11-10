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

    // Does this platform's CCI-P implementation support byte write ranges?
    parameter BYTE_EN_SUPPORTED = 1,

    parameter ADD_TIMING_REG_STAGES = 0
    )
   (
    // CCI-P interface to FIU
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    // Generated Avalon host memory interface
    ofs_plat_avalon_mem_rdwr_if.to_source_clk host_mem_to_afu,

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
    ofs_plat_avalon_mem_rdwr_if_reg_sink_clk
      #(
        .N_REG_STAGES(ADD_TIMING_REG_STAGES + 1)
        )
      conn_afu_clk
       (
        .mem_source(host_mem_to_afu),
        .mem_sink(avmm_afu_clk_if)
        );

    //
    // Cross to the FIU clock, sort responses and map bursts to FIU sizes.
    //

    // ofs_plat_avalon_mem_rdwr_if_async_rob records the ROB indices
    // of read and write requests in rd_user and wr_user fields after the
    // UC_AVALON_UFLAGs. Size the user fields using whichever index space
    // is larger.
    localparam ROB_IDX_WIDTH =
        $clog2((MAX_ACTIVE_RD_LINES > MAX_ACTIVE_WR_LINES) ? MAX_ACTIVE_RD_LINES :
                                                             MAX_ACTIVE_WR_LINES);
    localparam USER_WIDTH =
        ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_MAX + 1 + ROB_IDX_WIDTH;

    function automatic logic [ROB_IDX_WIDTH-1:0] robIdxFromUser(logic [USER_WIDTH-1:0] user);
        return user[USER_WIDTH-1 : ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_MAX+1];
    endfunction // robIdxFromUser

    function automatic logic [USER_WIDTH-1:0] robIdxToUser(logic [ROB_IDX_WIDTH-1:0] idx);
        logic [USER_WIDTH-1:0] user = 0;
        user[USER_WIDTH-1 : ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_MAX+1] = idx;
        return user;
    endfunction // robIdxToUser

    ofs_plat_avalon_mem_rdwr_if
      #(
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN),
        `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_MEM_PARAMS(avmm_afu_clk_if),
        // CCI-P supports up to 4 line bursts
        .BURST_CNT_WIDTH(3),
        .USER_WIDTH(USER_WIDTH)
        )
      avmm_fiu_clk_if();

    assign avmm_fiu_clk_if.clk = clk;
    assign avmm_fiu_clk_if.reset_n = reset_n;
    assign avmm_fiu_clk_if.instance_number = to_fiu.instance_number;

    ofs_plat_map_avalon_mem_rdwr_if_to_host_mem
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .NATURAL_ALIGNMENT(1),
        .MAX_ACTIVE_RD_LINES(MAX_ACTIVE_RD_LINES),
        .MAX_ACTIVE_WR_LINES(MAX_ACTIVE_WR_LINES),
        .USER_ROB_IDX_START(ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_MAX+1)
        )
      rob
       (
        .mem_source(avmm_afu_clk_if),
        .mem_sink(avmm_fiu_clk_if)
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
        to_fiu.sTx.c0.hdr.mdata <= t_ccip_mdata'(robIdxFromUser(avmm_fiu_clk_if.rd_user));
        to_fiu.sTx.c0.hdr.address <= avmm_fiu_clk_if.rd_address;
        to_fiu.sTx.c0.hdr.req_type <= eREQ_RDLINE_I;
        to_fiu.sTx.c0.hdr.cl_len <= t_ccip_clLen'(avmm_fiu_clk_if.rd_burstcount - 3'b1);

        if (!reset_n)
        begin
            to_fiu.sTx.c0.valid <= 1'b0;
        end
    end

    // CCI-P read responses
    always_ff @(posedge clk)
    begin
        avmm_fiu_clk_if.rd_readdatavalid <= ccip_c0Rx_isReadRsp(sRx.c0);
        avmm_fiu_clk_if.rd_readdata <= sRx.c0.data;
        // Index of the ROB entry
        avmm_fiu_clk_if.rd_readresponseuser <= robIdxToUser(sRx.c0.hdr.mdata + sRx.c0.hdr.cl_num);
        // Use the no reply flag to indicate the beat isn't SOP. If cl_num isn't 0
        // then the beat is not SOP.
        avmm_fiu_clk_if.rd_readresponseuser[ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_NO_REPLY] <=
            |(sRx.c0.hdr.cl_num);

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

    // Decoding masked writes into CCI-P's range encoding takes two cycles.
    // Generate most of the request into c1Tx while the range is prepared.
    t_if_ccip_c1_Tx c1Tx, c1Tx_q;

    // CCI-P doesn't return mdata with interrupt responses. There are only four
    // interrupt vectors. Save the ROB index. Interrupts are sorted in the same
    // ROB as write responses.
    logic [ROB_IDX_WIDTH-1:0] intrRobIdx[4];

    always_ff @(posedge clk)
    begin
        c1Tx.valid <= wr_beat_valid;
        c1Tx.data <= avmm_fiu_clk_if.wr_writedata;

        if (wr_sop)
        begin
            c1Tx.hdr <= t_ccip_c1_ReqMemHdr'(0);
            c1Tx.hdr.mdata <= t_ccip_mdata'(robIdxFromUser(avmm_fiu_clk_if.wr_user));

            if ((avmm_fiu_clk_if.USER_WIDTH > ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_FENCE) &
                avmm_fiu_clk_if.wr_user[ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_FENCE])
            begin
                // Write fence. req_type and mdata are in the same places in the
                // header as a normal write.
                c1Tx.hdr.req_type <= eREQ_WRFENCE;
            end
            else if ((avmm_fiu_clk_if.USER_WIDTH > ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_INTERRUPT) &
                avmm_fiu_clk_if.wr_user[ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_INTERRUPT])
            begin
                // Write fence. req_type and mdata are in the same places in the
                // header as a normal write.
                c1Tx.hdr.req_type <= eREQ_INTR;
                // Low two bits of the interrupt header are the ID (overlayed with mdata).
                // Avalon passes them in the address field.
                c1Tx.hdr.mdata <= '0;
                c1Tx.hdr.mdata[1:0] <= avmm_fiu_clk_if.wr_address[1:0];
                // Save the rob index so the interrupt response can be sorted.
                if (wr_beat_valid)
                begin
                    intrRobIdx[avmm_fiu_clk_if.wr_address[1:0]] <=
                        robIdxFromUser(avmm_fiu_clk_if.wr_user);
                end
            end
            else
            begin
                // Normal write
                c1Tx.hdr.address <= avmm_fiu_clk_if.wr_address;
                c1Tx.hdr.req_type <= eREQ_WRLINE_I;
                c1Tx.hdr.cl_len <= t_ccip_clLen'(avmm_fiu_clk_if.wr_burstcount - 3'b1);
                c1Tx.hdr.sop <= 1'b1;
            end
        end
        else
        begin
            c1Tx.hdr.address[1:0] <= wr_cl_addr | wr_cl_num;
            c1Tx.hdr.sop <= 1'b0;
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

        c1Tx_q <= c1Tx;

        if (!reset_n)
        begin
            c1Tx.valid <= 1'b0;
            c1Tx_q.valid <= 1'b0;
            wr_sop <= 1'b1;
            wr_cl_len <= eCL_LEN_1;
            wr_cl_num <= t_ccip_clNum'(0);
        end
    end

    // Decode masked range
    t_ccip_mem_access_mode wr_mode;
    t_ccip_clByteIdx wr_byte_start, wr_byte_len;

    ofs_plat_utils_ccip_decode_bmask bmask
       (
        .clk,
        .reset_n,
        .bmask(avmm_fiu_clk_if.wr_byteenable),
        .T2_wr_mode(wr_mode),
        .T2_byte_start(wr_byte_start),
        .T2_byte_len(wr_byte_len)
        );

    // Forward write request to the FIU
    always_comb
    begin
        to_fiu.sTx.c1 = c1Tx_q;

        if (BYTE_EN_SUPPORTED &&
            ((c1Tx_q.hdr.req_type == eREQ_WRLINE_I) || (c1Tx_q.hdr.req_type == eREQ_WRLINE_M)))
        begin
            to_fiu.sTx.c1.hdr.mode = wr_mode;
            to_fiu.sTx.c1.hdr.byte_start = wr_byte_start;
            to_fiu.sTx.c1.hdr.byte_len = wr_byte_len;
        end
    end

    // synthesis translate_off
    always_ff @(posedge clk)
    begin
        if (reset_n && (BYTE_EN_SUPPORTED == 0))
        begin
            if (c1Tx_q.valid &&
                (wr_mode == eMOD_BYTE) &&
                ((c1Tx_q.hdr.req_type == eREQ_WRLINE_I) || (c1Tx_q.hdr.req_type == eREQ_WRLINE_M)))
            begin
                $fatal(2, "CCI-P byte range write not supported on this platform!");
            end
        end
    end
    // synthesis translate_on


    always_ff @(posedge clk)
    begin
        avmm_fiu_clk_if.wr_writeresponsevalid <=
            (ccip_c1Rx_isWriteRsp(sRx.c1) ||
             ccip_c1Rx_isWriteFenceRsp(sRx.c1) ||
             ccip_c1Rx_isInterruptRsp(sRx.c1));

        // Index of the ROB entry. Responses are already guaranteed packed by
        // the PIM's CCI-P shim.
        avmm_fiu_clk_if.wr_writeresponseuser <= robIdxToUser(sRx.c1.hdr.mdata);

        // Interrupts only have a vector index in their responses. Recover the
        // ROB index.
        if (sRx.c1.hdr.resp_type == eRSP_INTR)
        begin
            avmm_fiu_clk_if.wr_writeresponseuser <=
                robIdxToUser(intrRobIdx[sRx.c1.hdr.mdata[1:0]]);
        end

        if (!reset_n)
        begin
            avmm_fiu_clk_if.wr_writeresponsevalid <= 1'b0;
        end
    end

    assign avmm_fiu_clk_if.wr_response = 2'b0;

endmodule // ofs_plat_map_ccip_as_avalon_host_mem
