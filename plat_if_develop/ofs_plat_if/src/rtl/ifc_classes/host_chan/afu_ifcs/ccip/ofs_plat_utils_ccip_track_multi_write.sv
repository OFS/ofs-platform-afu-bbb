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
// Track the beats of multi-line CCI-P write requests.
//

`include "ofs_plat_if.vh"

module ofs_plat_utils_ccip_track_multi_write
   (
    input  logic clk,
    input  logic reset_n,

    // Channel to monitor
    input  t_if_ccip_c1_Tx c1Tx,
    // Was the message at the head of the channel processed?
    input  logic c1Tx_en,

    // Is the current beat the end of the packet?
    output logic eop,

    // True if in the middle of a multi-line packet.
    output logic packetActive,
    // Next beat number expected in the current packet
    output t_ccip_clNum nextBeatNum
    );

    import ofs_plat_ccip_if_funcs_pkg::*;

    always_comb
    begin
        eop = 1'b1;

        if (ccip_c1Tx_isWriteReq(c1Tx))
        begin
            eop = (nextBeatNum == c1Tx.hdr.cl_len);
        end
    end

    // Track the beat number
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            nextBeatNum <= t_ccip_clNum'(0);
            packetActive <= 1'b0;
        end
        else if (ccip_c1Tx_isWriteReq(c1Tx) && c1Tx_en)
        begin
            if (nextBeatNum == c1Tx.hdr.cl_len)
            begin
                // Last beat in the packet
                nextBeatNum <= t_ccip_clNum'(0);
                packetActive <= 1'b0;
            end
            else
            begin
                nextBeatNum <= nextBeatNum + t_ccip_clNum'(1);
                packetActive <= 1'b1;
            end

            // synthesis translate_off
            // SOP marker should come only when no packet is active
            assert(c1Tx.hdr.sop == ! packetActive) else
                $fatal(2, "** ERROR ** %m: SOP out of phase");

            assert(packetActive == (nextBeatNum != 0)) else
                $fatal(2, "** ERROR ** %m: packetActive out of phase");
            // synthesis translate_on
        end
    end

endmodule // ofs_plat_utils_ccip_track_multi_write
