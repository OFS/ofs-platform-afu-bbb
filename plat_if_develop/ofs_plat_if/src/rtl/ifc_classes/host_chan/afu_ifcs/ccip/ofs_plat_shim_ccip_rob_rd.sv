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
// This shim accomplishes two things:
//
//   - CCI-P read responses are sorted so they are returned in request order.
//
//   - CCI-P mdata is modified on requests so that every in-flight read
//     request has a unique mdata value within the range defined by
//     the MAX_ACTIVE_RD_REQS parameter. The entire mdata field is preserved.
//

`include "ofs_plat_if.vh"

module ofs_plat_shim_ccip_rob_rd
  #(
    // Maximum number of in-flight read requests
    parameter MAX_ACTIVE_RD_REQS = ccip_cfg_pkg::C0_MAX_BW_ACTIVE_LINES[0],

    // Extra stages to add to usual almost full threshold
    parameter THRESHOLD_EXTRA = 6
    )
   (
    // Connection toward the FIU
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    // Connection toward the AFU
    ofs_plat_host_ccip_if.to_afu to_afu
    );

    import ofs_plat_ccip_if_funcs_pkg::*;

    // Treat MAX_ACTIVE_RD_REQS as both the maximum number of requests
    // of any size and the maximum number of lines outstanding.  It turns
    // out that maximum throughput is typically reached with the same
    // number of lines outstanding, independent of request size.  Of
    // course the bandwidth may vary as a function of request size.
    localparam MAX_ACTIVE_LINES = 1 << $clog2(MAX_ACTIVE_RD_REQS);

    // Maximum number of beats in a multi-line request
    parameter CCIP_MAX_MULTI_LINE_BEATS = 1 << $bits(t_ccip_clNum);

    wire clk;
    assign clk = to_fiu.clk;
    assign to_afu.clk = to_fiu.clk;

    assign to_afu.error = to_fiu.error;
    assign to_afu.reset_n = to_fiu.reset_n;
    assign to_afu.instance_number = to_fiu.instance_number;

    logic reset_n = 1'b0;
    always @(posedge clk)
    begin
        reset_n <= to_fiu.reset_n;
    end

    // Index of a request
    localparam N_REQ_IDX_BITS = $clog2(MAX_ACTIVE_LINES);
    typedef logic [N_REQ_IDX_BITS-1 : 0] t_req_idx;

    // Full signals that will come from the ROB and heap used to
    // sort responses.
    logic rd_not_full;

    // ====================================================================
    //
    //  The ROB is allocated with enough reserved space so that
    //  it honors the almost full semantics. No other buffering is
    //  required.
    //
    // ====================================================================

    assign to_afu.sRx.c0TxAlmFull = to_fiu.sRx.c0TxAlmFull || ! rd_not_full;


    // ====================================================================
    //
    //  Channel 0 (read)
    //
    // ====================================================================

    t_req_idx rd_rob_allocIdx;

    logic rd_rob_deq_en;
    logic rd_rob_notEmpty;
    logic rd_rob_data_rdy;
    t_ccip_mdata rd_rob_mdata;

    logic rd_rob_sop;
    logic rd_rob_eop;
    t_ccip_clNum rd_rob_cl_num;
    logic rd_rob_error;
    t_ccip_vc rd_rob_vc_used;
    logic rd_rob_hit_miss;
    t_ccip_clData rd_rob_out_data;

    // Read response index is the base index allocated by the
    // c0Tx read request plus the beat offset for multi-line reads.
    t_req_idx rd_rob_rsp_idx;
    always_ff @(posedge clk)
    begin
        rd_rob_rsp_idx <= t_req_idx'(to_fiu.sRx.c0.hdr.mdata) +
                          t_req_idx'(to_fiu.sRx.c0.hdr.cl_num);
    end

    t_ccip_mdata rd_sop_mdata;
    t_ccip_mdata rd_beat_mdata;

    t_ccip_clNum rd_packet_len;
    t_ccip_clNum rd_sop_packet_len;
    t_ccip_clNum rd_beat_packet_len;

    t_if_ccip_c0_Rx c0Rx_q, c0Rx_qq;

    //
    // Read responses are sorted.  Allocate a reorder buffer.
    //
    ofs_plat_prim_rob
      #(
        // MAX_ACTIVE_LINES is used here for clarity, since the ROB
        // is line-based.
        .N_ENTRIES(MAX_ACTIVE_LINES),
        .N_DATA_BITS(1 + $bits(t_ccip_vc) + 1 + $bits(t_ccip_clNum) + CCIP_CLDATA_WIDTH),
        .N_META_BITS($bits(t_ccip_clNum) + CCIP_MDATA_WIDTH),
        .MIN_FREE_SLOTS((CCIP_TX_ALMOST_FULL_THRESHOLD + THRESHOLD_EXTRA) * CCIP_MAX_MULTI_LINE_BEATS),
        .MAX_ALLOC_PER_CYCLE(CCIP_MAX_MULTI_LINE_BEATS)
        )
      rd_rob
       (
        .clk,
        .reset_n,

        .alloc_en(ccip_c0Tx_isReadReq(to_afu.sTx.c0)),
        .allocCnt(3'(to_afu.sTx.c0.hdr.cl_len) + 3'(1)),
        .allocMeta({ to_afu.sTx.c0.hdr.cl_len, to_afu.sTx.c0.hdr.mdata }),
        .notFull(rd_not_full),
        .allocIdx(rd_rob_allocIdx),
        .inSpaceAvail(),

        .enqData_en(ccip_c0Rx_isReadRsp(c0Rx_q)),
        .enqDataIdx(rd_rob_rsp_idx),
        .enqData({ c0Rx_q.hdr.error, c0Rx_q.hdr.vc_used, c0Rx_q.hdr.hit_miss, c0Rx_q.hdr.cl_num, c0Rx_q.data }),

        .deq_en(rd_rob_deq_en),
        .notEmpty(rd_rob_notEmpty),
        .T2_first({ rd_rob_error, rd_rob_vc_used, rd_rob_hit_miss, rd_rob_cl_num, rd_rob_out_data }),
        .T2_firstMeta({ rd_beat_packet_len, rd_beat_mdata })
        );


    // ROB data appears 2 cycles after notEmpty is asserted
    logic rd_rob_deq_en_q;
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            rd_rob_deq_en_q <= 1'b0;
            rd_rob_data_rdy <= 1'b0;
        end
        else
        begin
            rd_rob_deq_en_q <= rd_rob_deq_en;
            rd_rob_data_rdy <= rd_rob_deq_en_q;
        end
    end

    // Responses are now ordered.  Mark EOP when the last flit is
    // forwarded.
    assign rd_rob_eop = (rd_rob_cl_num == rd_packet_len);

    // SOP must follow EOP
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            rd_rob_sop <= 1'b1;
        end
        else if (rd_rob_data_rdy)
        begin
            rd_rob_sop <= rd_rob_eop;

            // synthesis translate_off
            assert (rd_rob_sop == (rd_rob_cl_num == 0)) else
                $fatal(2, "** ERROR ** %m: Incorrect rd_rob_sop calculation!");
            // synthesis translate_on
        end
    end

    // The mdata field stored in the ROB is valid only for the first
    // beat in multi-line responses.  Since responses are ordered
    // we can preserve valid mdata and return it with the remaining
    // flits in a packet.
    always_comb
    begin
        if (rd_rob_sop)
        begin
            rd_rob_mdata = rd_beat_mdata;
            rd_packet_len = rd_beat_packet_len;
        end
        else
        begin
            rd_rob_mdata = rd_sop_mdata;
            rd_packet_len = rd_sop_packet_len;
        end
    end

    always_ff @(posedge clk)
    begin
        if (rd_rob_data_rdy && rd_rob_sop)
        begin
            rd_sop_mdata <= rd_beat_mdata;
            rd_sop_packet_len <= rd_beat_packet_len;
        end
    end

    // Forward requests toward the FIU.  Replace the mdata entry with the
    // ROB index.  The original mdata is saved in the rob and restored
    // when the response is returned.
    always_comb
    begin
        to_fiu.sTx.c0 = to_afu.sTx.c0;
        to_fiu.sTx.c0.hdr.mdata = t_ccip_mdata'(rd_rob_allocIdx);
    end


    //
    // Responses
    //

    // The ROB has a 2 cycle latency. When the ROB is not empty decide when
    // to deq based on whether the fiu is empty. The ROB response will be merged
    // into the afu response two cycles later.
    always_ff @(posedge clk)
    begin
        c0Rx_q <= to_fiu.sRx.c0;
        c0Rx_qq <= c0Rx_q;
    end

    logic c0_non_rd_valid;

    always_comb
    begin
        // Is there a non-read response active?
        c0_non_rd_valid = ccip_c0Rx_isValid(to_fiu.sRx.c0) &&
                          ! ccip_c0Rx_isReadRsp(to_fiu.sRx.c0);

        rd_rob_deq_en = rd_rob_notEmpty && ! c0_non_rd_valid;
    end


    always_comb
    begin
        to_afu.sRx.c0 = c0Rx_qq;

        // Either forward the header from the FIU for non-read responses or
        // reconstruct the read response header.
        if (rd_rob_data_rdy)
        begin
            to_afu.sRx.c0.hdr = t_ccip_c0_RspMemHdr'(0);
            to_afu.sRx.c0.hdr.resp_type = eRSP_RDLINE;
            to_afu.sRx.c0.hdr.mdata = rd_rob_mdata;
            to_afu.sRx.c0.hdr.cl_num = rd_rob_cl_num;
            to_afu.sRx.c0.hdr.error = rd_rob_error;
            to_afu.sRx.c0.hdr.vc_used = rd_rob_vc_used;
            to_afu.sRx.c0.hdr.hit_miss = rd_rob_hit_miss;
            to_afu.sRx.c0.data = rd_rob_out_data;
            to_afu.sRx.c0.rspValid = 1'b1;
        end
        else if (ccip_c0Rx_isReadRsp(c0Rx_qq))
        begin
            // Read response comes from the ROB, not the FIU directly
            to_afu.sRx.c0.rspValid = 1'b0;
        end
    end


    // ====================================================================
    //
    //  Channel 1 (write) flows straight through.
    //
    // ====================================================================

    assign to_fiu.sTx.c1 = to_afu.sTx.c1;

    assign to_afu.sRx.c1TxAlmFull = to_fiu.sRx.c1TxAlmFull;
    assign to_afu.sRx.c1 = to_fiu.sRx.c1;


    // ====================================================================
    //
    // Channel 2 Tx (MMIO read response) flows straight through.
    //
    // ====================================================================

    assign to_fiu.sTx.c2 = to_afu.sTx.c2;

endmodule // ofs_plat_shim_ccip_rob_rd
