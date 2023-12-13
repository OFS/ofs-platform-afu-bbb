// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Initialization modules for standard clocks.
//

`include "ofs_plat_if.vh"

//
// Map the standard AFU clocks to the PIM's clocks structure. A vector of
// soft resets is passed in, one reset per host channel port. Each reset
// is mapped to all the clock domains.
//
module ofs_plat_std_clocks_gen_port_resets
  #(
    parameter NUM_PORTS = `OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS
    )
   (
    input  logic pClk,
    input  logic [NUM_PORTS - 1 : 0] pClk_reset_n,

    input  logic pClkDiv2,
    input  logic pClkDiv4,
    input  logic uClk_usr,
    input  logic uClk_usrDiv2,

    output t_ofs_plat_std_clocks clocks
    );

    generate
        for (genvar p = 0; p < NUM_PORTS; p = p + 1)
        begin : port
            ofs_plat_std_afu_clocks_gen_resets r
               (
                .pClk,
                .pClk_reset_n(pClk_reset_n[p]),
                .pClkDiv2,
                .pClkDiv4,
                .uClk_usr,
                .uClk_usrDiv2,
                .clocks(clocks.ports[p])
                );
        end
    endgenerate

    // Top-level clocks and resets from port 0 for backward compatibility
    assign clocks.pClk = clocks.ports[0].pClk;
    assign clocks.pClkDiv2 = clocks.ports[0].pClkDiv2;
    assign clocks.pClkDiv4 = clocks.ports[0].pClkDiv4;
    assign clocks.uClk_usr = clocks.ports[0].uClk_usr;
    assign clocks.uClk_usrDiv2 = clocks.ports[0].uClk_usrDiv2;

endmodule // ofs_plat_std_clocks_gen_port_resets


//
// Legacy constructor for an AFU's clocks, with soft reset mapped to each
// clock domain.
//
// The legacy version assumes only a single host channel port. (No VFs or
// extra PFs.) Only a single soft reset is passed in.
//
module ofs_plat_std_clocks_gen_resets
   (
    input  logic pClk,
    input  logic pClk_reset_n,

    input  logic pClkDiv2,
    input  logic pClkDiv4,
    input  logic uClk_usr,
    input  logic uClk_usrDiv2,

    output t_ofs_plat_std_clocks clocks
    );

    ofs_plat_std_afu_clocks_gen_resets r
       (
        .pClk,
        .pClk_reset_n,
        .pClkDiv2,
        .pClkDiv4,
        .uClk_usr,
        .uClk_usrDiv2,
        .clocks(clocks.ports[0])
        );

    // Top-level clocks and resets from port 0 for backward compatibility
    assign clocks.pClk = clocks.ports[0].pClk;
    assign clocks.pClkDiv2 = clocks.ports[0].pClkDiv2;
    assign clocks.pClkDiv4 = clocks.ports[0].pClkDiv4;
    assign clocks.uClk_usr = clocks.ports[0].uClk_usr;
    assign clocks.uClk_usrDiv2 = clocks.ports[0].uClk_usrDiv2;

endmodule // ofs_plat_std_clocks_gen_resets


//
// Legacy variant of ofs_plat_std_clocks_gen_resets() with an incoming
// active high reset.
//
module ofs_plat_std_clocks_gen_resets_from_active_high
   (
    input  logic pClk,
    input  logic pClk_reset,

    input  logic pClkDiv2,
    input  logic pClkDiv4,
    input  logic uClk_usr,
    input  logic uClk_usrDiv2,

    output t_ofs_plat_std_clocks clocks
    );

    (* preserve *) logic reset_n = 1'b0;
    always @(posedge pClk)
    begin
        reset_n <= !pClk_reset;
    end

    ofs_plat_std_clocks_gen_resets r
       (
        .pClk,
        .pClk_reset_n(reset_n),
        .pClkDiv2,
        .pClkDiv4,
        .uClk_usr,
        .uClk_usrDiv2,
        .clocks
        );

endmodule // ofs_plat_std_clocks_gen_resets_from_active_high


//
// Map a reset (presumably, a port-specific soft reset) to all the standard
// clock domains.
//
module ofs_plat_std_afu_clocks_gen_resets
   (
    input  logic pClk,
    input  logic pClk_reset_n,

    input  logic pClkDiv2,
    input  logic pClkDiv4,
    input  logic uClk_usr,
    input  logic uClk_usrDiv2,

    output t_ofs_plat_std_afu_clocks clocks
    );

    assign clocks.pClk.clk = pClk;
    assign clocks.pClkDiv2.clk = pClkDiv2;
    assign clocks.pClkDiv4.clk = pClkDiv4;
    assign clocks.uClk_usr.clk = uClk_usr;
    assign clocks.uClk_usrDiv2.clk = uClk_usrDiv2;

    logic softreset_n = 1'b0;
    assign clocks.pClk.reset_n = softreset_n;

    // Guarantee reset is never 'x in simulation
    always @(posedge pClk)
    begin
        softreset_n <= pClk_reset_n;

        // synthesis translate_off
        if (pClk_reset_n === 1'bx) softreset_n <= 1'b0;
        // synthesis translate_on
    end

    ofs_plat_prim_clock_crossing_reset pClkDiv2_reset
       (
        .clk_src(pClk),
        .clk_dst(pClkDiv2),
        .reset_in(softreset_n),
        .reset_out(clocks.pClkDiv2.reset_n)
        );

    ofs_plat_prim_clock_crossing_reset pClkDiv4_reset
       (
        .clk_src(pClk),
        .clk_dst(pClkDiv4),
        .reset_in(softreset_n),
        .reset_out(clocks.pClkDiv4.reset_n)
        );

    ofs_plat_prim_clock_crossing_reset uClk_usr_reset
       (
        .clk_src(pClk),
        .clk_dst(uClk_usr),
        .reset_in(softreset_n),
        .reset_out(clocks.uClk_usr.reset_n)
        );

    ofs_plat_prim_clock_crossing_reset uClk_usrDiv2_reset
       (
        .clk_src(pClk),
        .clk_dst(uClk_usrDiv2),
        .reset_in(softreset_n),
        .reset_out(clocks.uClk_usrDiv2.reset_n)
        );

endmodule // ofs_plat_std_afu_clocks_gen_resets
