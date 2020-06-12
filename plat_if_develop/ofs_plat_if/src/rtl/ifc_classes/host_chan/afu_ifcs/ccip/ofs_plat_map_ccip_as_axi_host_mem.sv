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
    // Cross to the FIU clock, sort responses and map bursts to FIU sizes.
    //

    // ofs_plat_axi_mem_if_async_rob records the ROB indices of read and
    // write requests in user fields after the HC_AXI_UFLAGs. Size the user
    // fields using whichever index space is larger.
    localparam ROB_IDX_WIDTH =
        $clog2((MAX_ACTIVE_RD_LINES > MAX_ACTIVE_WR_LINES) ? MAX_ACTIVE_RD_LINES :
                                                             MAX_ACTIVE_WR_LINES);
    localparam USER_WIDTH =
        ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_MAX + 1 + ROB_IDX_WIDTH;

    function automatic logic [ROB_IDX_WIDTH-1:0] robIdxFromUser(logic [USER_WIDTH-1:0] user);
        return user[USER_WIDTH-1 : ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_MAX+1];
    endfunction // robIdxFromUser

    function automatic logic [USER_WIDTH-1:0] robIdxToUser(logic [ROB_IDX_WIDTH-1:0] idx);
        logic [USER_WIDTH-1:0] user = 0;
        user[USER_WIDTH-1 : ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_MAX+1] = idx;
        return user;
    endfunction // robIdxToUser

    ofs_plat_axi_mem_if
      #(
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN),
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_MEM_PARAMS(host_mem_to_afu),
        // CCI-P supports up to 4 line bursts
        .BURST_CNT_WIDTH(2),
        .RID_WIDTH(host_mem_to_afu.RID_WIDTH_),
        .WID_WIDTH(host_mem_to_afu.WID_WIDTH_),
        .USER_WIDTH(USER_WIDTH)
        )
      axi_fiu_clk_if();

    assign axi_fiu_clk_if.clk = clk;
    assign axi_fiu_clk_if.reset_n = reset_n;
    assign axi_fiu_clk_if.instance_number = to_fiu.instance_number;

    ofs_plat_map_axi_mem_if_to_host_mem
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .NATURAL_ALIGNMENT(1),
        .MAX_ACTIVE_RD_LINES(MAX_ACTIVE_RD_LINES),
        .MAX_ACTIVE_WR_LINES(MAX_ACTIVE_WR_LINES),
        .USER_ROB_IDX_START(ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_MAX+1)
        )
      rob
       (
        .mem_master(axi_afu_clk_if),
        .mem_slave(axi_fiu_clk_if)
        );


    //
    // Convert AXI to CCI-P. AXI clocks and burst sizes in axi_fiu_clk_if are
    // the same as CCI-P.
    //

    // AXI uses byte-level addressing, CCI-P uses line-level addressing.
    localparam AXI_LINE_START_BIT = host_mem_to_afu.ADDR_WIDTH_ - CCIP_CLADDR_WIDTH;

    //
    // Host memory reads
    //
    always_ff @(posedge clk)
    begin
        // Map almost full to AXI ready
        axi_fiu_clk_if.arready <= !sRx.c0TxAlmFull;

        to_fiu.sTx.c0.valid <= axi_fiu_clk_if.arvalid && axi_fiu_clk_if.arready;

        to_fiu.sTx.c0.hdr <= t_ccip_c0_ReqMemHdr'(0);
        // Store length in mdata along with the ROB index in order to detect the
        // last read response.
        to_fiu.sTx.c0.hdr.mdata <= t_ccip_mdata'({ axi_fiu_clk_if.ar.len,
                                                   robIdxFromUser(axi_fiu_clk_if.ar.user) });
        to_fiu.sTx.c0.hdr.address <= axi_fiu_clk_if.ar.addr[AXI_LINE_START_BIT +: CCIP_CLADDR_WIDTH];
        to_fiu.sTx.c0.hdr.req_type <= eREQ_RDLINE_I;
        to_fiu.sTx.c0.hdr.cl_len <= t_ccip_clLen'(axi_fiu_clk_if.ar.len);

        if (!reset_n)
        begin
            to_fiu.sTx.c0.valid <= 1'b0;
        end
    end

    // CCI-P read responses
    always_ff @(posedge clk)
    begin
        axi_fiu_clk_if.rvalid <= ccip_c0Rx_isReadRsp(sRx.c0);

        axi_fiu_clk_if.r <= '0;
        axi_fiu_clk_if.r.data <= sRx.c0.data;
        // Index of the ROB entry
        axi_fiu_clk_if.r.user <= robIdxToUser(sRx.c0.hdr.mdata + sRx.c0.hdr.cl_num);
        // The request length was stored in mdata in order to tag the last read
        // response.
        axi_fiu_clk_if.r.last <=
            (sRx.c0.hdr.mdata[ROB_IDX_WIDTH +: $bits(t_ccip_clNum)] == sRx.c0.hdr.cl_num);

        if (!reset_n)
        begin
            axi_fiu_clk_if.rvalid <= 1'b0;
        end
    end

    //
    // Host memory writes
    //

    // AXI interface used internally as a convenient way to recreate
    // the data structures.
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(axi_fiu_clk_if),
        .DISABLE_CHECKER(1)
        )
      axi_reg();

    //
    // Push write requests through FIFOs so the control and data can be
    // synchronized for CCI-P.
    //
    logic wr_sop;
    logic fwd_wr_req;

    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(axi_reg.T_AW_WIDTH)
        )
      aw_fifo
       (
        .clk,
        .reset_n,
        .enq_data(axi_fiu_clk_if.aw),
        .enq_en(axi_fiu_clk_if.awready && axi_fiu_clk_if.awvalid),
        .notFull(axi_fiu_clk_if.awready),
        .first(axi_reg.aw),
        .deq_en(fwd_wr_req && wr_sop),
        .notEmpty(axi_reg.awvalid)
        );

    // Write data
    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(axi_reg.T_W_WIDTH)
        )
      w_fifo
       (
        .clk,
        .reset_n,
        .enq_data(axi_fiu_clk_if.w),
        .enq_en(axi_fiu_clk_if.wready && axi_fiu_clk_if.wvalid),
        .notFull(axi_fiu_clk_if.wready),
        .first(axi_reg.w),
        .deq_en(fwd_wr_req),
        .notEmpty(axi_reg.wvalid)
        );

    assign fwd_wr_req = !sRx.c1TxAlmFull &&
                        (axi_reg.awvalid || !wr_sop) &&
                        axi_reg.wvalid;

    logic wr_eop;
    assign wr_eop = axi_reg.w.last;

    t_ccip_clLen wr_cl_len;
    t_ccip_clNum wr_cl_num;
    t_ccip_clNum wr_cl_addr;

    // Decoding masked writes into CCI-P's range encoding takes two cycles.
    // Generate most of the request into c1Tx while the range is prepared.
    t_if_ccip_c1_Tx c1Tx, c1Tx_q;

    always_ff @(posedge clk)
    begin
        c1Tx.valid <= fwd_wr_req;
        c1Tx.data <= axi_reg.w.data;

        if (wr_sop)
        begin
            c1Tx.hdr <= t_ccip_c1_ReqMemHdr'(0);
            c1Tx.hdr.mdata <= t_ccip_mdata'(robIdxFromUser(axi_reg.aw.user));
            c1Tx.hdr.req_type <= eREQ_WRLINE_I;
            c1Tx.hdr.sop <= 1'b1;

            if (axi_reg.aw.user[ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_FENCE])
            begin
                c1Tx.hdr.req_type <= eREQ_WRFENCE;
                c1Tx.hdr.sop <= 1'b0;
            end

            c1Tx.hdr.address <= axi_reg.aw.addr[AXI_LINE_START_BIT +: CCIP_CLADDR_WIDTH];
            c1Tx.hdr.cl_len <= t_ccip_clLen'(axi_reg.aw.len);
        end
        else
        begin
            c1Tx.hdr.address[1:0] <= wr_cl_addr | wr_cl_num;
            c1Tx.hdr.sop <= 1'b0;
        end

        // Update multi-line state
        if (fwd_wr_req)
        begin
            if (wr_sop)
            begin
                wr_cl_len <= t_ccip_clLen'(axi_reg.aw.len);
                wr_cl_addr <= axi_reg.aw.addr[AXI_LINE_START_BIT +: $bits(t_ccip_clNum)];
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
        .bmask(axi_reg.w.strb),
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
        axi_fiu_clk_if.bvalid <=
            (ccip_c1Rx_isWriteRsp(sRx.c1) || ccip_c1Rx_isWriteFenceRsp(sRx.c1));

        // Index of the ROB entry. Responses are already guaranteed packed by
        // the PIM's CCI-P shim.
        axi_fiu_clk_if.b <= '0;
        axi_fiu_clk_if.b.user <= robIdxToUser(sRx.c1.hdr.mdata);

        if (!reset_n)
        begin
            axi_fiu_clk_if.bvalid <= 1'b0;
        end
    end

    assign to_fiu.sTx.c2 = '0;

endmodule // ofs_plat_map_ccip_as_axi_host_mem
