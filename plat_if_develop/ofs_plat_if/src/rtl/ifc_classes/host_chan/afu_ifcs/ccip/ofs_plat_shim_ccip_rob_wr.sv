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
//   - CCI-P write responses are sorted so they are returned in request order.
//     This module always sets the "format" bit in the resopnse header, so
//     there is always exactly one ACK per write packet, independent of the
//     number of lines written. To use this module it is likely that the
//     ofs_plat_shim_ccip_detect_eop module is also required to ensure that
//     all multi-line write responses are merged.
//
//   - CCI-P mdata is modified on requests so that every in-flight write
//     request has a unique mdata value within the range defined by
//     the MAX_ACTIVE_RD_REQS parameter. The entire mdata field is preserved.
//

`include "ofs_plat_if.vh"

module ofs_plat_shim_ccip_rob_wr
  #(
    // Maximum number of in-flight write requests
    parameter MAX_ACTIVE_WR_REQS = ccip_cfg_pkg::C1_MAX_BW_ACTIVE_LINES[0],

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
    localparam N_REQ_IDX_BITS = $clog2(MAX_ACTIVE_WR_REQS);
    typedef logic [N_REQ_IDX_BITS-1 : 0] t_req_idx;


    // ====================================================================
    //
    //  Channel 0 (read) flows straight through.
    //
    // ====================================================================

    assign to_fiu.sTx.c0 = to_afu.sTx.c0;

    assign to_afu.sRx.c0TxAlmFull = to_fiu.sRx.c0TxAlmFull;
    assign to_afu.sRx.c0 = to_fiu.sRx.c0;



    // ====================================================================
    //
    //  Channel 1 (write)
    //
    // ====================================================================

    // Full signals that will come from the ROB and heap used to
    // sort responses.
    logic wr_not_full;

    // ====================================================================
    //
    //  The ROB is allocated with enough reserved space so that
    //  it honors the almost full semantics. No other buffering is
    //  required.
    //
    // ====================================================================

    assign to_afu.sRx.c1TxAlmFull = to_fiu.sRx.c1TxAlmFull || ! wr_not_full;

    t_req_idx wr_rob_allocIdx, wr_rob_allocIdx_prev;

    logic wr_rob_deq_en;
    logic wr_rob_notEmpty;
    logic wr_rob_rsp_rdy;

    logic wr_rsp_is_wrfence;
    t_ccip_c1_rsp wr_rob_rsp;

    // Number of write buffer entries to allocate.  More than one must be
    // allocated to hold multi-beat write responses. CCI-P allows
    // up to 4 lines per request, one line per beat.
    logic do_alloc;
    assign do_alloc = (ccip_c1Tx_isWriteReq(to_afu.sTx.c1) && to_afu.sTx.c1.hdr.sop) ||
                       ccip_c1Tx_isWriteFenceReq(to_afu.sTx.c1);

    // Write response index is stored in mdata.
    t_req_idx wr_rob_rsp_idx;
    always_ff @(posedge clk)
    begin
        wr_rob_rsp_idx <= t_req_idx'(to_fiu.sRx.c1.hdr.mdata);
    end

    t_ccip_mdata wr_rsp_mdata;
    t_ccip_c1_RspMemHdr wr_rsp_hdr;
    t_if_ccip_c1_Rx c1Rx_q, c1Rx_qq;

    //
    // Write responses are sorted.  Allocate a reorder buffer.
    //
    ofs_plat_prim_rob
      #(
        .N_ENTRIES(MAX_ACTIVE_WR_REQS),
        .N_DATA_BITS($bits(t_ccip_c1_RspMemHdr)),
        .N_META_BITS(CCIP_MDATA_WIDTH),
        .MIN_FREE_SLOTS(CCIP_TX_ALMOST_FULL_THRESHOLD + THRESHOLD_EXTRA),
        .MAX_ALLOC_PER_CYCLE(1)
        )
      wr_rob
       (
        .clk,
        .reset_n,

        .alloc_en(do_alloc),
        .allocCnt(1'b1),
        .allocMeta(to_afu.sTx.c1.hdr.mdata),
        .notFull(wr_not_full),
        .allocIdx(wr_rob_allocIdx),
        .inSpaceAvail(),

        .enqData_en(ccip_c1Rx_isWriteRsp(c1Rx_q) || ccip_c1Rx_isWriteFenceRsp(c1Rx_q)),
        .enqDataIdx(wr_rob_rsp_idx),
        .enqData(c1Rx_q.hdr),

        .deq_en(wr_rob_deq_en),
        .notEmpty(wr_rob_notEmpty),
        .T2_first(wr_rsp_hdr),
        .T2_firstMeta(wr_rsp_mdata)
        );


    // ROB data appears 2 cycles after notEmpty is asserted
    logic wr_rob_deq_en_q;
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            wr_rob_deq_en_q <= 1'b0;
            wr_rob_rsp_rdy <= 1'b0;
        end
        else
        begin
            wr_rob_deq_en_q <= wr_rob_deq_en;
            wr_rob_rsp_rdy <= wr_rob_deq_en_q;
        end
    end

    // Forward requests toward the FIU.  Replace the mdata entry with the
    // ROB index.  The original mdata is saved in the rob and restored
    // when the response is returned.
    always_comb
    begin
        to_fiu.sTx.c1 = to_afu.sTx.c1;

        if (do_alloc)
        begin
            to_fiu.sTx.c1.hdr.mdata = t_ccip_mdata'(wr_rob_allocIdx);
        end
        else if (ccip_c1Tx_isWriteReq(to_afu.sTx.c1))
        begin
            to_fiu.sTx.c1.hdr.mdata = t_ccip_mdata'(wr_rob_allocIdx_prev);
        end
    end

    // Preserve mdata for multi-line writes
    always_ff @(posedge clk)
    begin
        if (do_alloc)
        begin
            wr_rob_allocIdx_prev <= wr_rob_allocIdx;
        end

        if (!reset_n)
        begin
            wr_rob_allocIdx_prev <= 0;
        end
    end


    //
    // Responses
    //

    // The ROB has a 2 cycle latency. When the ROB is not empty decide when
    // to deq based on whether the fiu is empty. The ROB response will be merged
    // into the afu response two cycles later.
    always_ff @(posedge clk)
    begin
        c1Rx_q <= to_fiu.sRx.c1;
        c1Rx_qq <= c1Rx_q;
    end

    logic c1_non_wr_valid;

    always_comb
    begin
        // Is there a non-write response active?
        c1_non_wr_valid = ccip_c1Rx_isValid(to_fiu.sRx.c1) &&
                          ! ccip_c1Rx_isWriteRsp(to_fiu.sRx.c1) &&
                          ! ccip_c1Rx_isWriteFenceRsp(to_fiu.sRx.c1);

        wr_rob_deq_en = wr_rob_notEmpty && ! c1_non_wr_valid;
    end


    always_comb
    begin
        to_afu.sRx.c1 = c1Rx_qq;

        // Either forward the header from the FIU for non-write responses or
        // reconstruct the write response header.
        if (wr_rob_rsp_rdy)
        begin
            to_afu.sRx.c1.hdr = wr_rsp_hdr;
            to_afu.sRx.c1.hdr.mdata = wr_rsp_mdata;
            to_afu.sRx.c1.rspValid = 1'b1;
        end
        else if (ccip_c1Rx_isWriteRsp(c1Rx_qq) || ccip_c1Rx_isWriteFenceRsp(c1Rx_qq))
        begin
            // Write response comes from the ROB, not the FIU directly
            to_afu.sRx.c1.rspValid = 1'b0;
        end
    end


    // ====================================================================
    //
    // Channel 2 Tx (MMIO read response) flows straight through.
    //
    // ====================================================================

    assign to_fiu.sTx.c2 = to_afu.sTx.c2;

endmodule // ofs_plat_shim_ccip_rob_wr
