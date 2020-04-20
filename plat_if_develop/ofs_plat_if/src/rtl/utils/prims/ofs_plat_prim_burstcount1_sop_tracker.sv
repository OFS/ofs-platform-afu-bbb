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
// This module operate on burst counts with an origin of 1, where "1" means
// one beat and "0" is illegal. This is the Avalon encoding.
//

//
// Track requests on a channel with flits broken down into packets. (E.g. an
// Avalon write channel.) Detect SOP and EOP by tracking burst (packet) lengths.
//
module ofs_plat_prim_burstcount1_sop_tracker
  #(
    parameter BURST_CNT_WIDTH = 0
    )
   (
    input  logic clk,
    input  logic reset_n,

    // Process a flit (update counters)
    input  logic flit_valid,
    // Consumed only at SOP -- the length of the next burst
    input  logic [BURST_CNT_WIDTH-1 : 0] burstcount,

    output logic sop,
    output logic eop
    );

    typedef logic [BURST_CNT_WIDTH-1:0] t_burstcount;
    t_burstcount flits_rem;

    always_ff @(posedge clk)
    begin
        if (flit_valid)
        begin
            if (sop)
            begin
                flits_rem <= burstcount - t_burstcount'(1);
                sop <= (burstcount == t_burstcount'(1));
            end
            else
            begin
                flits_rem <= flits_rem - t_burstcount'(1);
                sop <= (flits_rem == t_burstcount'(1));
            end
        end

        if (!reset_n)
        begin
            flits_rem <= t_burstcount'(0);
            sop <= 1'b1;
        end
    end

    assign eop = (sop && (burstcount == t_burstcount'(1))) ||
                 (!sop && (flits_rem == t_burstcount'(1)));

endmodule // ofs_plat_prim_burstcount1_sop_tracker
