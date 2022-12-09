// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// FIFO --
//   A FIFO with N_ENTRIES storage elements and signaling almostFull when
//   THRESHOLD or fewer slots are free, stored in block RAM.
//

`include "ofs_plat_if.vh"

module ofs_plat_prim_fifo_bram
  #(
    parameter N_DATA_BITS = 32,
    parameter N_ENTRIES = 2,
    parameter THRESHOLD = 1
    )
   (
    input  logic clk,
    input  logic reset_n,

    input  logic [N_DATA_BITS-1 : 0] enq_data,
    input  logic                     enq_en,
    output logic                     notFull,
    output logic                     almostFull,

    output logic [N_DATA_BITS-1 : 0] first,
    input  logic                     deq_en,
    output logic                     notEmpty
    );

    logic sc_full;
    assign notFull = ! sc_full;

    logic sc_empty;
    logic sc_rdreq;

    // Read from BRAM FIFO "first" is available and the FIFO has data.
    assign sc_rdreq = (! notEmpty || deq_en) && ! sc_empty;

    always_ff @(posedge clk)
    begin
        // Not empty if first was already valid and there was no deq or the
        // BRAM FIFO has valid data.
        notEmpty <= (notEmpty && ! deq_en) || ! sc_empty;

        if (!reset_n)
        begin
            notEmpty <= 1'b0;
        end
    end

    scfifo
      #(
`ifdef PLATFORM_INTENDED_DEVICE_FAMILY
        .intended_device_family(`PLATFORM_INTENDED_DEVICE_FAMILY),
`endif
        .lpm_numwords(N_ENTRIES),
        .lpm_showahead("OFF"),
        .lpm_type("scfifo"),
        .lpm_width(N_DATA_BITS),
        .lpm_widthu($clog2(N_ENTRIES)),
        .almost_full_value(N_ENTRIES - THRESHOLD),
        .overflow_checking("OFF"),
        .underflow_checking("OFF"),
        .use_eab("ON"),
        .add_ram_output_register("ON")
        )
      scfifo_component
       (
        .clock(clk),
        .sclr(!reset_n),

        .data(enq_data),
        .wrreq(enq_en),
        .full(sc_full),
        .almost_full(almostFull),

        .rdreq(sc_rdreq),
        .q(first),
        .empty(sc_empty),
        .almost_empty(),

        .aclr(),
        .usedw(),
        .eccstatus()
        );

    // synthesis translate_off

    always_ff @(posedge clk)
    begin
        if (reset_n)
        begin
            assert (! (sc_full && enq_en)) else
                $fatal(2, "** ERROR ** %m: ENQ to full SCFIFO");

            assert (notEmpty || ! deq_en) else
                $fatal(2, "** ERROR ** %m: DEQ from empty SCFIFO");
        end
    end

    // synthesis translate_on

endmodule // ofs_plat_prim_fifo_bram
