//
// Copyright (c) 2020, Intel Corporation
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

        .rdReqCnt(rd_n_lines_req),
        .rdRespCnt(3'(rd_is_line_rsp)),

        .events
        );

endmodule // host_chan_events_ccip
