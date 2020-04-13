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
// For multi-beat writes, CCI-P allows either individual write responses or
// a single packed response. Having to deal with both can be inconvenient.
// This shim transforms unpacked responses into a single packed response,
// guaranteeing that all writes return exactly one packed ACK.
//
// IMPORTANT NOTE:
//   This module depends on c1Tx mdata holding unique values in the low
//   bits (see MAX_ACTIVE_WR_REQS below).
//

`include "ofs_plat_if.vh"

module ofs_plat_shim_ccip_detect_eop
  #(
    // The maximum number of write requests on c1Tx indicates the number
    // of low bits in c1Tx.hdr.mdata to use as a unique tag for each
    // active write request. Logic between this module and the AFU must
    // guarantee that values are unique! The tags are used inside the
    // EOP detector.
    parameter MAX_ACTIVE_WR_REQS = ccip_cfg_pkg::C1_MAX_BW_ACTIVE_LINES[0]
    )
   (
    // Connection toward the FIU
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    // Connection toward the AFU
    ofs_plat_host_ccip_if.to_afu to_afu
    );

    import ofs_plat_ccip_if_funcs_pkg::*;

    logic clk;
    assign clk = to_fiu.clk;
    assign to_afu.clk = to_fiu.clk;

    logic reset_n;
    assign reset_n = to_fiu.reset_n;
    assign to_afu.reset_n = to_fiu.reset_n;

    assign to_afu.instance_number = to_fiu.instance_number;

    // Index of a request
    localparam N_REQ_IDX_BITS = $clog2(MAX_ACTIVE_WR_REQS);
    typedef logic [N_REQ_IDX_BITS-1 : 0] t_req_idx;


    // ====================================================================
    //
    //  Channel 0 (read) is passed through as wires.
    //
    // ====================================================================

    assign to_fiu.sTx.c0 = to_afu.sTx.c0;

    assign to_afu.sRx.c0TxAlmFull = to_fiu.sRx.c0TxAlmFull;
    assign to_afu.sRx.c0 = to_fiu.sRx.c0;


    // ====================================================================
    //
    //  Channel 1 (write) -- Merge multi-beat responses.
    //
    // ====================================================================

    //
    // Monitor flow of requests and responses.
    //

    logic wr_rsp_mon_rdy;
    assign to_afu.sRx.c1TxAlmFull = to_fiu.sRx.c1TxAlmFull || ! wr_rsp_mon_rdy;

    t_if_ccip_c1_Rx c1Rx[0:1];
    t_ccip_clNum wr_rsp_packet_len;
    logic wr_rsp_pkt_eop;

    ofs_plat_shim_ccip_detect_eop_track_flits
      #(
        .MAX_ACTIVE_REQS(MAX_ACTIVE_WR_REQS)
        )
      c1_tracker
       (
        .clk,
        .reset_n,
        .rdy(wr_rsp_mon_rdy),

        .req_en(ccip_c1Tx_isWriteReq(to_afu.sTx.c1)),
        .reqIdx(t_req_idx'(to_afu.sTx.c1.hdr.mdata)),
        .reqLen(to_afu.sTx.c1.hdr.cl_len),

        .rsp_en(ccip_c1Rx_isWriteRsp(c1Rx[0])),
        .rspIdx(t_req_idx'(c1Rx[0].hdr.mdata)),
        .rspIsPacked(c1Rx[0].hdr.format),

        .T1_pkt_eop(wr_rsp_pkt_eop),
        .T1_rspLen(wr_rsp_packet_len)
        );


    //
    // Requests
    //
    assign to_fiu.sTx.c1 = to_afu.sTx.c1;


    //
    // Responses. The latency of write responses isn't that important, within reason.
    // Register c1Rx[0] to relax timing.
    //
    //
    always_ff @(posedge clk)
    begin
        c1Rx[0] <= to_fiu.sRx.c1;
        c1Rx[1] <= c1Rx[0];
    end

    always_ff @(posedge clk)
    begin
        to_afu.sRx.c1 <= c1Rx[1];

        // If wr_rsp_pkt_eop is 0 then this flit is a write response and it
        // isn't the end of the packet.  Drop it.  The response will be
        // merged into a single flit.
        to_afu.sRx.c1.rspValid <=
            c1Rx[1].rspValid &&
            (wr_rsp_pkt_eop || ! ccip_c1Rx_isWriteRsp(c1Rx[1]));

        // Merge write responses for a packet into single response.
        if (ccip_c1Rx_isWriteRsp(c1Rx[1]))
        begin
            to_afu.sRx.c1.hdr.format <= 1'b1;
            to_afu.sRx.c1.hdr.cl_num <= wr_rsp_packet_len;
        end
    end


    // ====================================================================
    //
    // Channel 2 Tx (MMIO read response) flows straight through.
    //
    // ====================================================================

    assign to_fiu.sTx.c2 = to_afu.sTx.c2;

endmodule // ofs_plat_shim_ccip_detect_eop


//
// Control code for monitoring requests and responses on a channel and
// detecting the flit that is the last response for a packet.
//
module ofs_plat_shim_ccip_detect_eop_track_flits
  #(
    MAX_ACTIVE_REQS = 128
    )
   (
    input  logic clk,
    input  logic reset_n,
    output logic rdy,

    // New request to track
    input  logic req_en,
    input  logic [$clog2(MAX_ACTIVE_REQS)-1 : 0] reqIdx,
    input  t_ccip_clNum reqLen,

    // New response
    input  logic rsp_en,
    input  logic [$clog2(MAX_ACTIVE_REQS)-1 : 0] rspIdx,
    input  logic rspIsPacked,

    //
    // Responses arrive 2 cycles after requests
    //

    // Is response the end of the packet?
    output logic T1_pkt_eop,
    // Full length of the flit's packet
    output t_ccip_clNum T1_rspLen
    );

    typedef logic [$clog2(MAX_ACTIVE_REQS)-1 : 0] t_heap_idx;

    //
    // Requests
    //

    // Packet size of outstanding requests.  Separating this from the count
    // of responses avoids dealing with multiple writers to either memory.

    // Write is registered for timing.
    logic req_en_q;
    t_heap_idx reqIdx_q;
    t_ccip_clNum reqLen_q;

    ofs_plat_prim_lutram_banked
      #(
        .N_ENTRIES(MAX_ACTIVE_REQS),
        .N_DATA_BITS($bits(t_ccip_clNum)),
        .READ_DURING_WRITE("DONT_CARE"),
        .N_BANKS(2)
        )
      packet_len
       (
        .clk,
        .reset_n,

        .raddr(rspIdx),
        .T1_rdata(T1_rspLen),

        .waddr(reqIdx_q),
        .wen(req_en_q),
        .wdata(reqLen_q)
        );

    always_ff @(posedge clk)
    begin
        reqIdx_q <= reqIdx;
        req_en_q <= req_en;
        reqLen_q <= reqLen;
        if (!reset_n)
        begin
            req_en_q <= 1'b0;
        end
    end


    //
    // Responses
    //

    logic T1_rspIsPacked;
    t_heap_idx T1_rspIdx, T2_rspIdx;
    logic T1_rsp_en, T2_rsp_en;
    t_ccip_clNum T1_wdata, T2_wdata;
    t_ccip_clNum T1_flitCnt;
    t_ccip_clNum T1_flitCnt_ram;

    ofs_plat_prim_lutram_init_banked
      #(
        .N_ENTRIES(MAX_ACTIVE_REQS),
        .N_DATA_BITS($bits(t_ccip_clNum)),
        .READ_DURING_WRITE("NEW_DATA"),
        .N_BANKS(2)
        )
      flit_cnt
       (
        .clk,
        .reset_n,
        .rdy,

        .raddr(rspIdx),
        .T1_rdata(T1_flitCnt_ram),

        .waddr(T2_rspIdx),
        .wen(T2_rsp_en),
        .wdata(T2_wdata)
        );

    always_ff @(posedge clk)
    begin
        T1_rspIsPacked <= rspIsPacked;
        T1_rspIdx <= rspIdx;
        T1_rsp_en <= rsp_en;

        // Writes are delayed one cycle for timing
        T2_rspIdx <= T1_rspIdx;
        T2_rsp_en <= T1_rsp_en;
        T2_wdata <= T1_wdata;

        if (!reset_n)
        begin
            T1_rsp_en <= 1'b0;
            T2_rsp_en <= 1'b0;
        end
    end


    // Is a bypass needed due to delayed writes?
    logic bypass_en;
    always_ff @(posedge clk)
    begin
        bypass_en <= T1_rsp_en && (T1_rspIdx == rspIdx);
    end

    assign T1_flitCnt = (bypass_en ? T2_wdata : T1_flitCnt_ram);


    // Is the packet complete?
    assign T1_pkt_eop = (T1_rspLen == T1_flitCnt) || T1_rspIsPacked;

    // Update internal flit count.
    assign T1_wdata = (T1_pkt_eop ? t_ccip_clNum'(0) : T1_flitCnt + t_ccip_clNum'(1));

endmodule // ofs_plat_shim_ccip_detect_eop_track_flits
