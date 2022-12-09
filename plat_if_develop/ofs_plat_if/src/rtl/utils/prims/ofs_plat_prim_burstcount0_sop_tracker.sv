// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


//
// Theis module operates on burst counts with an origin of 0, where "0" means
// one beat. This is the AXI encoding.
//

//
// Track requests on a channel with flits broken down into packets. (E.g. an
// Avalon write channel.) Detect SOP and EOP by tracking burst (packet) lengths.
//
module ofs_plat_prim_burstcount0_sop_tracker
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
                sop <= (burstcount == t_burstcount'(0));
            end
            else
            begin
                flits_rem <= flits_rem - t_burstcount'(1);
                sop <= (flits_rem == t_burstcount'(0));
            end
        end

        if (!reset_n)
        begin
            flits_rem <= t_burstcount'(0);
            sop <= 1'b1;
        end
    end

    assign eop = (sop && (burstcount == t_burstcount'(0))) ||
                 (!sop && (flits_rem == t_burstcount'(0)));

endmodule // ofs_plat_prim_burstcount0_sop_tracker
