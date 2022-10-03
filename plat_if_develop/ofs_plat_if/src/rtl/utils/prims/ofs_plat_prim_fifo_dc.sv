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
// FIFO --
//   A dual clock FIFO with N_ENTRIES storage elements and signaling
//   almostFull when THRESHOLD or fewer slots are free, stored in block RAM.
//

`include "ofs_plat_if.vh"

module ofs_plat_prim_fifo_dc
  #(
    parameter N_DATA_BITS = 32,
    parameter N_ENTRIES = 4,
    parameter THRESHOLD = 1
    )
   (
    input  logic enq_clk,
    input  logic enq_reset_n,
    input  logic [N_DATA_BITS-1 : 0] enq_data,
    input  logic enq_en,
    output logic notFull,
    output logic almostFull,

    input  logic deq_clk,
    input  logic deq_reset_n,
    output logic [N_DATA_BITS-1 : 0] first,
    input  logic deq_en,
    output logic notEmpty
    );

    // There are two implementations of dual clock FIFO available. One uses
    // the DCFIFO megafunction and the other uses an Avalon primitive.
    // The megafunction closed timing more reliably on older versions of
    // Quartus, used by the Xeon+FPGA integrated parts. The Avalon clock
    // crossing FIFO is generally faster and smaller with recent tools.
`ifdef PLATFORM_FPGA_INTG_XEON
    localparam USE_DCFIFO_MF = 1;
`else
    localparam USE_DCFIFO_MF = 0;
`endif

    generate
        if (USE_DCFIFO_MF != 0)
        begin : mf
            ofs_plat_prim_fifo_dc_mf
              #(
                .N_DATA_BITS(N_DATA_BITS),
                .N_ENTRIES(N_ENTRIES),
                .THRESHOLD(THRESHOLD)
                )
              f
               (
                .enq_clk,
                .enq_reset_n,
                .enq_data,
                .enq_en,
                .notFull,
                .almostFull,

                .deq_clk,
                .deq_reset_n,
                .first,
                .deq_en,
                .notEmpty
                );
        end
        else
        begin : af
            ofs_plat_prim_fifo_dc_af
              #(
                .N_DATA_BITS(N_DATA_BITS),
                .N_ENTRIES(N_ENTRIES),
                .THRESHOLD(THRESHOLD)
                )
              f
               (
                .enq_clk,
                .enq_reset_n,
                .enq_data,
                .enq_en,
                .notFull,
                .almostFull,

                .deq_clk,
                .deq_reset_n,
                .first,
                .deq_en,
                .notEmpty
                );
        end
    endgenerate

endmodule // ofs_plat_prim_fifo_dc


//
// Wrapper around the megafunction dual clock FIFO.
//
module ofs_plat_prim_fifo_dc_mf
  #(
    parameter N_DATA_BITS = 32,
    parameter N_ENTRIES = 2,
    parameter THRESHOLD = 1
    )
   (
    input  logic enq_clk,
    input  logic enq_reset_n,
    input  logic [N_DATA_BITS-1 : 0] enq_data,
    input  logic enq_en,
    output logic notFull,
    output logic almostFull,

    input  logic deq_clk,
    input  logic deq_reset_n,
    output logic [N_DATA_BITS-1 : 0] first,
    input  logic deq_en,
    output logic notEmpty
    );

    logic reset_n_async;
    ofs_plat_prim_clock_crossing_reset_async reset_async_cc
       (
        .clk(enq_clk),
        .reset_in(enq_reset_n),
        .reset_out(reset_n_async)
        );

    logic dcfifo_full;
    assign notFull = !dcfifo_full;

    logic dcfifo_rdreq, dcfifo_rdreq_q;
    logic dcfifo_empty;
    logic [N_DATA_BITS-1 : 0] dcfifo_q;

    ofs_plat_utils_mf_dcfifo
      #(
        .DATA_WIDTH(N_DATA_BITS),
        .DEPTH_RADIX($clog2(N_ENTRIES)),
        .ALMOST_FULL_THRESHOLD(THRESHOLD)
        )
      dcfifo
       (
        .data(enq_data),
        .wrreq(enq_en),
        .rdreq(dcfifo_rdreq),
        .wrclk(enq_clk),
        .rdclk(deq_clk),
        .aclr(!reset_n_async),
        .q(dcfifo_q),
        .rdusedw(),
        .wrusedw(),
        .rdfull(),
        .rdempty(dcfifo_empty),
        .wrfull(dcfifo_full),
        .wralmfull(almostFull),
        .wrempty()
        );

    //
    // The megafunction delivers the read data a cycle after "rdreq" is asserted.
    // The PIM FIFO primivites have "first" valid when "notEmpty". Add a FIFO
    // to map the megafunction to PIM semantics.
    //
    logic out_fifo_almFull;

    ofs_plat_prim_fifo_lutram
      #(
        .N_DATA_BITS(N_DATA_BITS),
        .N_ENTRIES(4),
        .THRESHOLD(2),
        .REGISTER_OUTPUT(1)
        )
      out_fifo
       (
        .clk(deq_clk),
        .reset_n(deq_reset_n),

        .enq_data(dcfifo_q),
        .enq_en(dcfifo_rdreq_q),
        .notFull(),
        .almostFull(out_fifo_almFull),

        .first,
        .deq_en,
        .notEmpty
        );

    assign dcfifo_rdreq = !dcfifo_empty && !out_fifo_almFull;

    always_ff @(posedge deq_clk)
    begin
        dcfifo_rdreq_q <= dcfifo_rdreq;
    end

endmodule // ofs_plat_prim_fifo_dc_mf


//
// Wrapper around the Avalon dual clock FIFO.
//
module ofs_plat_prim_fifo_dc_af
  #(
    parameter N_DATA_BITS = 32,
    parameter N_ENTRIES = 2,
    parameter THRESHOLD = 1
    )
   (
    input  logic enq_clk,
    input  logic enq_reset_n,
    input  logic [N_DATA_BITS-1 : 0] enq_data,
    input  logic enq_en,
    output logic notFull,
    output logic almostFull,

    input  logic deq_clk,
    input  logic deq_reset_n,
    output logic [N_DATA_BITS-1 : 0] first,
    input  logic deq_en,
    output logic notEmpty
    );

    typedef logic [$clog2(N_ENTRIES) : 0] t_entry_cnt;
    t_entry_cnt space_avail_cnt;
    logic in_ready;

    // Clock crossing FIFO
    (* altera_attribute = "-name ALLOW_ANY_RAM_SIZE_FOR_RECOGNITION ON" *) ofs_plat_utils_avalon_dc_fifo
      #(
        .SYMBOLS_PER_BEAT(1),
        .BITS_PER_SYMBOL(N_DATA_BITS),
        // Round up FIFO_DEPTH to a power of 2. The Avalon FIFO expects it.
        .FIFO_DEPTH(2 ** $clog2(N_ENTRIES)),
        .BACKPRESSURE_DURING_RESET(1),
        // Added for OPAE to drive s0_space_avail_data
        .USE_SPACE_AVAIL_IF (1)
        )
      dcfifo
       (
        .in_clk(enq_clk),
        .in_reset_n(enq_reset_n),
        .out_clk(deq_clk),
        .out_reset_n(deq_reset_n),

        .in_data(enq_data),
        .in_valid(enq_en),
        .in_ready(in_ready),

        .out_data(first),
        .out_valid(notEmpty),
        .out_ready(deq_en),

        .in_startofpacket(1'b0),
        .in_endofpacket(1'b0),
        .in_empty(1'b0),
        .in_error(1'b0),
        .in_channel(1'b0),
        .in_csr_address(1'b0),
        .in_csr_read(1'b0),
        .in_csr_write(1'b0),
        .in_csr_writedata(32'b0),
        .out_csr_address(1'b0),
        .out_csr_read(1'b0),
        .out_csr_write(1'b0),
        .out_csr_writedata(32'b0),

        .out_startofpacket(),
        .out_endofpacket(),
        .out_empty(),
        .out_error(),
        .out_channel(),
        .in_csr_readdata(),
        .out_csr_readdata(),
        .almost_full_valid(),
        .almost_full_data(),
        .almost_empty_valid(),
        .almost_empty_data(),
        .space_avail_data(space_avail_cnt)
        );


    localparam SAFE_THRESHOLD = 1 + (THRESHOLD > 2 ? THRESHOLD : 2);
    logic cnt_notFull;
    logic cnt_almostFull;

    always_ff @(posedge enq_clk)
    begin
        // Using the in_ready signal directly as notFull ought to work, but
        // sometimes fails in simulation when the internal buffer read and write
        // pointers are equal. Setting notFull to avoid pointer overlap solves
        // the problem and shouldn't affect throughput.
        cnt_notFull <= (t_entry_cnt'(space_avail_cnt) > 2);
        cnt_almostFull <= ~(t_entry_cnt'(space_avail_cnt) > SAFE_THRESHOLD);
    end

    assign notFull = cnt_notFull && in_ready;
    assign almostFull = cnt_almostFull || !in_ready;


    //
    // Error checking.
    //

    // synthesis translate_off
    initial
    begin
        assert (N_ENTRIES > 2) else
            $fatal(2, "** ERROR ** %m: FIFO is too small");
    end

    always_ff @(negedge enq_clk)
    begin
        if (enq_reset_n)
        begin
            assert (notFull || !enq_en) else
                $fatal(2, "** ERROR ** %m: ENQ to full FIFO");
        end
    end

    always_ff @(negedge deq_clk)
    begin
        if (deq_reset_n)
        begin
            assert (notEmpty || !deq_en) else
                $fatal(2, "** ERROR ** %m: DEQ from empty FIFO");
        end
    end
    // synthesis translate_on

endmodule // ofs_plat_prim_fifo_dc_af
