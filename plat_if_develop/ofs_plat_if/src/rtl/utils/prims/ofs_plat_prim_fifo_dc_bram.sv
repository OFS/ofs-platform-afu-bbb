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
// FIFO --
//   A dual clock FIFO with N_ENTRIES storage elements and signaling
//   almostFull when THRESHOLD or fewer slots are free, stored in block RAM.
//

`include "ofs_plat_if.vh"

module ofs_plat_prim_fifo_dc_bram
  #(
    parameter N_DATA_BITS = 32,
    parameter N_ENTRIES = 2,
    parameter THRESHOLD = 1
    )
   (
    input  logic reset,

    input  logic                     wr_clk,
    input  logic [N_DATA_BITS-1 : 0] enq_data,
    input  logic                     enq_en,
    output logic                     notFull,
    output logic                     almostFull,

    input  logic                     rd_clk,
    output logic [N_DATA_BITS-1 : 0] first,
    input  logic                     deq_en,
    output logic                     notEmpty
    );

    logic dc_full;
    assign notFull = ! dc_full;

    logic dc_empty;
    logic dc_rdreq;

    // Read from BRAM FIFO "first" is available and the FIFO has data.
    assign dc_rdreq = (! notEmpty || deq_en) && ! dc_empty;

    always_ff @(posedge rd_clk)
    begin
        // Not empty if first was already valid and there was no deq or the
        // BRAM FIFO has valid data.
        notEmpty <= (notEmpty && ! deq_en) || ! dc_empty;

        if (reset)
        begin
            notEmpty <= 1'b0;
        end
    end

    ofs_plat_utils_dc_fifo
      #(
        .DATA_WIDTH(N_DATA_BITS),
        .DEPTH_RADIX($clog2(N_ENTRIES)),
        .ALMOST_FULL_THRESHOLD(THRESHOLD)
        )
      dcfifo
       (
        .aclr(reset),

        .wrclk(wr_clk),
        .data(enq_data),
        .wrreq(enq_en),
        .wrfull(dc_full),
        .wralmfull(almostFull),

        .rdclk(rd_clk),
        .rdreq(dc_rdreq),
        .q(first),
        .rdempty(dc_empty),

        .wrempty(),
        .wrusedw(),
        .rdfull(),
        .rdusedw()
        );

    // synthesis translate_off

    always_ff @(posedge wr_clk)
    begin
        if (! reset)
        begin
            assert (! (dc_full && enq_en)) else
                $fatal(2, "** ERROR ** %m: ENQ to full SCFIFO");
        end
    end

    always_ff @(posedge rd_clk)
    begin
        if (! reset)
        begin
            assert (notEmpty || ! deq_en) else
                $fatal(2, "** ERROR ** %m: DEQ from empty SCFIFO");
        end
    end

    // synthesis translate_on

endmodule // ofs_plat_prim_fifo_bram
