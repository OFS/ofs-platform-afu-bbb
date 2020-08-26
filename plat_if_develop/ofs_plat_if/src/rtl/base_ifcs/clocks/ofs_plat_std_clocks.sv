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
// Initialization modules for standard clocks.
//

`include "ofs_plat_if.vh"

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

endmodule // ofs_plat_std_clocks_gen_resets


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

endmodule // ofs_plat_std_clocks_gen_resets
