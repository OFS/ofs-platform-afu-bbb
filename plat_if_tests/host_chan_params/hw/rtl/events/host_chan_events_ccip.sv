// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Host channel event tracker for native CCI-P
//

`include "ofs_plat_if.vh"

module host_chan_events_ccip
   (
    input  logic clk,
    input  logic reset_n,

    // Track traffic on sRx and sTx (in domain clk)
    input  t_if_ccip_Rx sRx,
    input  t_if_ccip_Tx sTx,

    // Send counted events to a specific traffic generator engine
    host_chan_events_if.monitor events
    );

    import ofs_plat_ccip_if_funcs_pkg::*;

    //
    // Track new requests and responses
    //
    typedef logic [2:0] t_line_count;
    t_line_count rd_n_lines_req;
    logic rd_is_line_rsp;

    always_ff @(posedge clk)
    begin
        // Request (potentially multiple lines)
        rd_n_lines_req <= '0;
        if (ccip_c0Tx_isReadReq(sTx.c0))
        begin
            rd_n_lines_req <= t_line_count'(sTx.c0.hdr.cl_len) + 1;
        end

        // Response (exactly one line)
        rd_is_line_rsp <= ccip_c0Rx_isReadRsp(sRx.c0);
    end


    //
    // Manage events
    //
    host_chan_events_common
      #(
        .READ_CNT_WIDTH(3)
        )
      hc_evt
       (
        .clk,
        .reset_n,

        .rdClk(clk),
        .rdReqCnt(rd_n_lines_req),
        .rdRespCnt(3'(rd_is_line_rsp)),

        .events
        );

endmodule // host_chan_events_ccip
