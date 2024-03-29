// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Track pending response counts on CCI-P channels.  These counts may be
// used for handing out request credits when responses are buffered.
//

import ccip_if_pkg::*;

module ofs_plat_utils_ccip_c0_active_cnt
  #(
    parameter C0RX_DEPTH_RADIX = 10
    )
   (
    input logic clk,
    input logic reset_n,

    input t_if_ccip_c0_Tx c0Tx,
    input t_if_ccip_c0_Rx c0Rx,

    output logic [C0RX_DEPTH_RADIX-1 : 0] cnt
    );

    typedef logic [C0RX_DEPTH_RADIX-1 : 0] t_active_cnt;

    logic [2:0] active_incr;
    logic active_decr;

    always_comb
    begin
        // Multi-beat read requests cause the activity counter to incremement
        // by the number of lines requested.
        if (c0Tx.valid)
        begin
            active_incr = 3'b1 + 3'(c0Tx.hdr.cl_len);
        end
        else
        begin
            active_incr = 3'b0;
        end

        // Only one line comes back at a time
        active_decr = c0Rx.rspValid && (c0Rx.hdr.resp_type == eRSP_RDLINE);
    end

    // Two stage counter improves timing but delays updates for a cycle.
    logic [3:0] active_delta;
    always_ff @(posedge clk)
    begin
        active_delta <= 4'(active_incr) - 4'(active_decr);
    end

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            cnt <= t_active_cnt'(0);
        end
        else
        begin
            cnt <= cnt + t_active_cnt'(signed'(active_delta));
        end
    end

endmodule // ofs_plat_utils_ccip_c0_active_cnt


module ofs_plat_utils_ccip_c1_active_cnt
  #(
    parameter C1RX_DEPTH_RADIX = 10
    )
   (
    input logic clk,
    input logic reset_n,

    input t_if_ccip_c1_Tx c1Tx,
    input t_if_ccip_c1_Rx c1Rx,

    output logic [C1RX_DEPTH_RADIX-1 : 0] cnt
    );

    typedef logic [C1RX_DEPTH_RADIX-1 : 0] t_active_cnt;

    logic active_incr;
    logic [2:0] active_decr;

    always_comb
    begin
        // New request?
        active_incr = c1Tx.valid;

        if (c1Rx.rspValid)
        begin
            if ((c1Rx.hdr.resp_type == eRSP_WRLINE) && c1Rx.hdr.format)
            begin
                // Packed response for multiple lines
                active_decr = 3'b1 + 3'(c1Rx.hdr.cl_num);
            end
            else
            begin
                // Response for a single request
                active_decr = 3'b1;
            end
        end
        else
        begin
            active_decr = 3'b0;
        end
    end

    // Two stage counter improves timing but delays updates for a cycle.
    logic [3:0] active_delta;
    always_ff @(posedge clk)
    begin
        active_delta <= 4'(active_incr) - 4'(active_decr);
    end

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            cnt <= t_active_cnt'(0);
        end
        else
        begin
            cnt <= cnt + t_active_cnt'(signed'(active_delta));
        end
    end

endmodule // ofs_plat_utils_ccip_c1_active_cnt
