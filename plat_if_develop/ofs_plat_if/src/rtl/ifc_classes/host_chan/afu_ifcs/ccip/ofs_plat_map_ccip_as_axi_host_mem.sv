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
    ofs_plat_axi_mem_if.to_source_clk host_mem_to_afu,

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

    ofs_plat_axi_mem_if_connect_sink_clk
      conn_afu_clk
       (
        .mem_source(host_mem_to_afu),
        .mem_sink(axi_afu_clk_if)
        );

    //
    // Cross to the FIU clock, sort responses and map bursts to FIU sizes.
    //

    // ofs_plat_axi_mem_if_async_rob records the ROB indices of read and
    // write requests in ID fields. The original values are recorded in the
    // ROB and returned to the source.
    localparam ROB_RID_WIDTH = $clog2(MAX_ACTIVE_RD_LINES);
    localparam ROB_WID_WIDTH = $clog2(MAX_ACTIVE_WR_LINES);

    ofs_plat_axi_mem_if
      #(
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN),
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_MEM_PARAMS(host_mem_to_afu),
        // CCI-P supports up to 4 line bursts
        .BURST_CNT_WIDTH(2),
        .USER_WIDTH(host_mem_to_afu.USER_WIDTH_),
        .RID_WIDTH(ROB_RID_WIDTH),
        .WID_WIDTH(ROB_WID_WIDTH)
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
        .MAX_ACTIVE_WR_LINES(MAX_ACTIVE_WR_LINES)
        )
      rob
       (
        .mem_source(axi_afu_clk_if),
        .mem_sink(axi_fiu_clk_if)
        );


    //
    // Convert AXI to CCI-P. AXI clocks and burst sizes in axi_fiu_clk_if are
    // the same as CCI-P.
    //

    // AXI uses byte-level addressing, CCI-P uses line-level addressing.
    localparam AXI_LINE_START_BIT = host_mem_to_afu.ADDR_BYTE_IDX_WIDTH;

    //
    // Host memory reads
    //
    always_comb
    begin
        to_fiu.sTx.c0.valid = axi_fiu_clk_if.arvalid && axi_fiu_clk_if.arready;

        to_fiu.sTx.c0.hdr = t_ccip_c0_ReqMemHdr'(0);
        // Store length in mdata along with the ROB index in order to detect the
        // last read response.
        to_fiu.sTx.c0.hdr.mdata = t_ccip_mdata'({ axi_fiu_clk_if.ar.len,
                                                  ROB_RID_WIDTH'(axi_fiu_clk_if.ar.id) });
        to_fiu.sTx.c0.hdr.address = axi_fiu_clk_if.ar.addr[AXI_LINE_START_BIT +: CCIP_CLADDR_WIDTH];
        to_fiu.sTx.c0.hdr.req_type = eREQ_RDLINE_I;
        to_fiu.sTx.c0.hdr.cl_len = t_ccip_clLen'(axi_fiu_clk_if.ar.len);
    end

    always_ff @(posedge clk)
    begin
        // Map almost full to AXI ready
        axi_fiu_clk_if.arready <= !sRx.c0TxAlmFull;
    end

    // CCI-P read responses
    always_ff @(posedge clk)
    begin
        axi_fiu_clk_if.rvalid <= ccip_c0Rx_isReadRsp(sRx.c0);

        axi_fiu_clk_if.r <= '0;
        axi_fiu_clk_if.r.data <= sRx.c0.data;
        // Index of the ROB entry. Inside the PIM we violate the AXI-MM standard
        // by adding the line index to the tag in order to form a unique ROB
        // index. By the time a response gets to the AFU, the RID will be valid
        // and conform to AXI-MM.
        axi_fiu_clk_if.r.id <= ROB_RID_WIDTH'(sRx.c0.hdr.mdata + sRx.c0.hdr.cl_num);
        // The request length was stored in mdata in order to tag the last read
        // response.
        axi_fiu_clk_if.r.last <=
            (sRx.c0.hdr.mdata[ROB_RID_WIDTH +: $bits(t_ccip_clNum)] == sRx.c0.hdr.cl_num);

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

    logic c1TxAlmFull;
    always_ff @(posedge clk)
    begin
        c1TxAlmFull <= sRx.c1TxAlmFull;
    end

    assign fwd_wr_req = !c1TxAlmFull &&
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

    // CCI-P doesn't return mdata with interrupt responses. There are only four
    // interrupt vectors. Save the ROB index. Interrupts are sorted in the same
    // ROB as write responses.
    logic [ROB_WID_WIDTH-1:0] intrRobIdx[4];

    always_ff @(posedge clk)
    begin
        c1Tx.valid <= fwd_wr_req;
        c1Tx.data <= axi_reg.w.data;

        if (wr_sop)
        begin
            c1Tx.hdr <= t_ccip_c1_ReqMemHdr'(0);
            c1Tx.hdr.mdata <= t_ccip_mdata'(axi_reg.aw.id);
            c1Tx.hdr.req_type <= eREQ_WRLINE_I;
            c1Tx.hdr.sop <= 1'b1;
            c1Tx.hdr.address <= axi_reg.aw.addr[AXI_LINE_START_BIT +: CCIP_CLADDR_WIDTH];
            c1Tx.hdr.cl_len <= t_ccip_clLen'(axi_reg.aw.len);

            if ((axi_reg.USER_WIDTH > ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_FENCE) &&
                axi_reg.aw.user[ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_FENCE])
            begin
                c1Tx.hdr.req_type <= eREQ_WRFENCE;
                c1Tx.hdr.sop <= 1'b0;
                c1Tx.hdr.address <= '0;
            end

            if ((axi_reg.USER_WIDTH > ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_INTERRUPT) &&
                axi_reg.aw.user[ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_INTERRUPT])
            begin
                c1Tx.hdr.req_type <= eREQ_INTR;
                c1Tx.hdr.sop <= 1'b0;
                c1Tx.hdr.address <= '0;

                // Low two bits of the interrupt header are the ID (overlayed with mdata).
                // AXI passes them in the address field.
                c1Tx.hdr.mdata <= '0;
                c1Tx.hdr.mdata[1:0] <= axi_reg.aw.addr[1:0];
                // Save the rob index so the interrupt response can be sorted.
                if (fwd_wr_req)
                begin
                    intrRobIdx[axi_reg.aw.addr[1:0]] <= axi_reg.aw.id;
                end
            end
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
            (ccip_c1Rx_isWriteRsp(sRx.c1) ||
             ccip_c1Rx_isWriteFenceRsp(sRx.c1) ||
             ccip_c1Rx_isInterruptRsp(sRx.c1));

        // Index of the ROB entry. Responses are already guaranteed packed by
        // the PIM's CCI-P shim.
        axi_fiu_clk_if.b <= '0;
        axi_fiu_clk_if.b.id <= ROB_WID_WIDTH'(sRx.c1.hdr.mdata);

        // Interrupts only have a vector index in their responses. Recover the
        // ROB index.
        if (sRx.c1.hdr.resp_type == eRSP_INTR)
        begin
            axi_fiu_clk_if.b.id <= intrRobIdx[sRx.c1.hdr.mdata[1:0]];
        end

        if (!reset_n)
        begin
            axi_fiu_clk_if.bvalid <= 1'b0;
        end
    end

    assign to_fiu.sTx.c2 = '0;

endmodule // ofs_plat_map_ccip_as_axi_host_mem
