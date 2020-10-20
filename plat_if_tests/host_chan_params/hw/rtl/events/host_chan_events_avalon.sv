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
// Host channel event tracker for native Avalon
//

`include "ofs_plat_if.vh"

module host_chan_events_avalon
  #(
    parameter BURST_CNT_WIDTH = 7
    )
   (
    input  logic clk,
    input  logic reset_n,

    // Track traffic on FIM Avalon interface
    input  logic en_tx_rd,
    input  logic [BURST_CNT_WIDTH-1 : 0] tx_rd_cnt,
    input  logic en_rx_rd,

    // Send counted events to a specific traffic generator engine
    host_chan_events_if.monitor events
    );

    //
    // Track new requests and responses
    //
    typedef logic [BURST_CNT_WIDTH-1 : 0] t_line_count;
    t_line_count rd_n_lines_req;
    logic rd_is_line_rsp;

    always_ff @(posedge clk)
    begin
        rd_n_lines_req <= (en_tx_rd ? tx_rd_cnt : '0);
        rd_is_line_rsp <= en_rx_rd;
    end


    //
    // Manage events
    //
    host_chan_events_common
      #(
        .READ_CNT_WIDTH(BURST_CNT_WIDTH)
        )
      hc_evt
       (
        .clk,
        .reset_n,

        .rdReqCnt(rd_n_lines_req),
        .rdRespCnt(BURST_CNT_WIDTH'(rd_is_line_rsp)),

        .events
        );

endmodule // host_chan_events_avalon
