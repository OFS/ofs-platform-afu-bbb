// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Round-robin arbiter, derived from the Altera Advanced Synthesis Cookbook.
//

module ofs_plat_prim_arb_rr
  #(
    parameter NUM_CLIENTS = 0
    )
   (
    input  logic clk,
    input  logic reset_n,

    input  logic ena,
    input  logic [NUM_CLIENTS-1: 0] request,

    // One hot grant (same cycle as request)
    output logic [NUM_CLIENTS-1 : 0] grant,
    output logic [$clog2(NUM_CLIENTS)-1 : 0] grantIdx
    );

    typedef logic [NUM_CLIENTS-1 : 0] t_vec;
    typedef logic [2*NUM_CLIENTS-1 : 0] t_dbl_vec;

    // Priority (one hot)
    t_vec base;

    t_dbl_vec dbl_request;
    assign dbl_request = {request, request};

    t_dbl_vec dbl_grant;
    assign dbl_grant = dbl_request & ~(dbl_request - base);

    t_vec grant_reduce;
    assign grant_reduce = dbl_grant[NUM_CLIENTS-1 : 0] |
                          dbl_grant[2*NUM_CLIENTS-1 : NUM_CLIENTS];

    generate
        if (NUM_CLIENTS > 1)
        begin : a
            always_comb
            begin
                grantIdx = 0;
                for (int i = 0; i < NUM_CLIENTS; i = i + 1)
                begin
                    grant[i] = grant_reduce[i] && ena;

                    if (grant_reduce[i])
                    begin
                        grantIdx = ($clog2(NUM_CLIENTS))'(i);
                    end
                end
            end

            // Record winner for next cycle's priority
            always_ff @(posedge clk)
            begin
                if (!reset_n)
                begin
                    base <= t_vec'(1);
                end
                else if (ena && |(request))
                begin
                    // Rotate grant left so that the slot after the current winner
                    // is given priority.
                    base <= { grant_reduce[NUM_CLIENTS-2 : 0],
                              grant_reduce[NUM_CLIENTS-1] };
                end
            end
        end
        else
        begin : na
            // Only one client. No arbiter required!
            assign grant = ena && request;
            assign grantIdx = 0;
        end
    endgenerate

endmodule // ofs_plat_prim_arb_rr
