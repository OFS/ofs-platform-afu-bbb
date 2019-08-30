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
// Generate a writeresponsevalid signal by tracking write requests.
// This module may be used when a writeresponsevalid signal is desired but
// the underlying device doesn't offer one.
//
module ofs_plat_avalon_mem_if_gen_write_response
  #(
    parameter BURST_CNT_WIDTH = 0
    )
   (
    input  logic clk,
    input  logic reset,

    input  logic write,
    input  logic waitrequest,
    input  logic [BURST_CNT_WIDTH-1 : 0] burstcount,

    output logic writeresponsevalid
    );

    typedef logic [BURST_CNT_WIDTH-1 : 0] t_burst_cnt;

    logic did_write, did_write_q;
    t_burst_cnt burst_cnt, bursts_rem;
    logic is_eop;

    always_ff @(posedge clk)
    begin
        // Did write data arrive?
        did_write <= write && ! waitrequest;
        did_write_q <= did_write;

        burst_cnt <= burstcount;
        if (did_write)
        begin
            // In the middle of a burst?
            if (bursts_rem != t_burst_cnt'(0))
            begin
                // Yes -- decrement the count
                is_eop <= (bursts_rem == t_burst_cnt'(1));
                bursts_rem <= bursts_rem - t_burst_cnt'(1);
            end
            else
            begin
                // Start of a new burst
                is_eop <= (burst_cnt == t_burst_cnt'(1));
                bursts_rem <= burst_cnt - t_burst_cnt'(1);
            end
        end

        // One write response is expected per burst, at the end of the burst.
        writeresponsevalid <= did_write_q && is_eop;
        if (reset)
        begin
            writeresponsevalid <= 1'b0;
            bursts_rem <= t_burst_cnt'(0);
        end
    end

endmodule // ofs_plat_avalon_mem_if_gen_write_response
