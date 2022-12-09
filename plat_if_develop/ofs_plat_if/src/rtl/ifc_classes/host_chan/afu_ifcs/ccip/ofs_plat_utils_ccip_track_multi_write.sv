// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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
