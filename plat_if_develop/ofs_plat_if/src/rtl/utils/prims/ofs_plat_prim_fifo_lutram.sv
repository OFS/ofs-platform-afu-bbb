// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// FIFO --
//   A FIFO with N_ENTRIES storage elements and signaling almostFull when
//   THRESHOLD or fewer slots are free.
//

module ofs_plat_prim_fifo_lutram
  #(
    parameter N_DATA_BITS = 32,
    parameter N_ENTRIES = 2,
    parameter THRESHOLD = 1,

    // Register output if non-zero
    parameter REGISTER_OUTPUT = 0,
    // Bypass to register when FIFO and register are empty?  This parameter
    // has meaning only when REGISTER_OUTPUT is set.
    parameter BYPASS_TO_REGISTER = 0
    )
   (
    input  logic clk,
    input  logic reset_n,

    input  logic [N_DATA_BITS-1 : 0] enq_data,
    input  logic enq_en,
    output logic notFull,
    output logic almostFull,

    output logic [N_DATA_BITS-1 : 0] first,
    input  logic deq_en,
    output logic notEmpty
    );

    logic fifo_deq;
    logic fifo_notEmpty;
    logic [N_DATA_BITS-1 : 0] fifo_first;

    logic enq_bypass_en;

    ofs_plat_prim_fifo_lutram_base
      #(
        .N_DATA_BITS(N_DATA_BITS),
        .N_ENTRIES(N_ENTRIES),
        .THRESHOLD(THRESHOLD)
        )
      fifo
       (
        .clk,
        .reset_n,
        .enq_data,
        .enq_en(enq_en && ! enq_bypass_en),
        .notFull,
        .almostFull,
        .first(fifo_first),
        .deq_en(fifo_deq),
        .notEmpty(fifo_notEmpty)
        );

    generate
        if (REGISTER_OUTPUT == 0)
        begin : nr
            assign first = fifo_first;
            assign notEmpty = fifo_notEmpty;
            assign fifo_deq = deq_en;
            assign enq_bypass_en = 1'b0;
        end
        else
        begin : r
            //
            // Add an output register stage.
            //
            logic first_reg_valid;
            logic [N_DATA_BITS-1 : 0] first_reg;

            assign first = first_reg;
            assign notEmpty = first_reg_valid;
            assign fifo_deq = fifo_notEmpty && (deq_en || ! first_reg_valid);

            // Bypass to outbound register it will be empty and the FIFO
            // is empty.
            assign enq_bypass_en = (BYPASS_TO_REGISTER != 0) &&
                                   (deq_en || ! first_reg_valid) &&
                                   ! fifo_notEmpty;

            always_ff @(posedge clk)
            begin
                if (enq_bypass_en)
                begin
                    // Bypass around FIFO when the FIFO is empty and
                    // BYPASS_TO_REGISTER is enabled.
                    first_reg_valid <= enq_en;
                    first_reg <= enq_data;
                end
                else if (deq_en || ! first_reg_valid)
                begin
                    first_reg_valid <= fifo_notEmpty;
                    first_reg <= fifo_first;
                end

                if (!reset_n)
                begin
                    first_reg_valid <= 1'b0;
                end
            end
        end
    endgenerate

endmodule // ofs_plat_prim_fifo_lutram


//
// Base implementation of the LUTRAM FIFO, used by the main wrapper above.
//
module ofs_plat_prim_fifo_lutram_base
  #(
    parameter N_DATA_BITS = 32,
    parameter N_ENTRIES = 2,
    parameter THRESHOLD = 1
    )
   (
    input  logic clk,
    input  logic reset_n,

    input  logic [N_DATA_BITS-1 : 0] enq_data,
    input  logic enq_en,
    output logic notFull,
    output logic almostFull,

    output logic [N_DATA_BITS-1 : 0] first,
    input  logic deq_en,
    output logic notEmpty
    );
     
    // Pointer to head/tail in storage
    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_idx;

    t_idx enq_idx;
    t_idx first_idx;

    ofs_plat_prim_lutram
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(N_DATA_BITS)
        )
      data
       (
        .clk,
        .reset_n,

        .raddr(first_idx),
        .rdata(first),

        // Write the data as long as the FIFO isn't full.  This leaves the
        // data path independent of control.  notFull/notEmpty will track
        // the control messages.
        .waddr(enq_idx),
        .wen(notFull),
        .wdata(enq_data)
        );

    ofs_plat_prim_fifo_lutram_ctrl
      #(
        .N_ENTRIES(N_ENTRIES),
        .THRESHOLD(THRESHOLD)
        )
      ctrl
       (
        .clk,
        .reset_n,
        .enq_idx,
        .enq_en,
        .notFull,
        .almostFull,
        .first_idx,
        .deq_en,
        .notEmpty
        );

endmodule // ofs_plat_prim_fifo_lutram_base


//
// Control logic for FIFOs
//
module ofs_plat_prim_fifo_lutram_ctrl
  #(
    parameter N_ENTRIES = 2,
    parameter THRESHOLD = 1
    )
   (
    input  logic clk,
    input  logic reset_n,

    output logic [$clog2(N_ENTRIES)-1 : 0] enq_idx,
    input  logic enq_en,
    output logic notFull,
    output logic almostFull,

    output logic [$clog2(N_ENTRIES)-1 : 0] first_idx,
    input  logic deq_en,
    output logic notEmpty
    );

    // Pointer to head/tail in storage
    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_idx;
    // Counter of active entries, leaving room to represent both 0 and N_ENTRIES.
    typedef logic [$clog2(N_ENTRIES+1)-1 : 0] t_counter;

    t_counter valid_cnt;
    t_counter valid_cnt_next;

    logic error;

    // Write pointer advances on ENQ
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            enq_idx <= 1'b0;
        end
        else if (enq_en)
        begin
            enq_idx <= (enq_idx == t_idx'(N_ENTRIES-1)) ? 0 : enq_idx + 1;
        end
    end

    // Read pointer advances on DEQ
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            first_idx <= 1'b0;
        end
        else if (deq_en)
        begin
            first_idx <= (first_idx == t_idx'(N_ENTRIES-1)) ? 0 : first_idx + 1;
        end
    end

    // Error checking. Block the FIFO if data would be lost, hopefully
    // making debugging easier.
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            error <= 1'b0;
        end
        else
        begin
            if (enq_en && ! notFull)
            begin
                error <= 1'b1;
                $fatal(2, "** ERROR ** %m: ENQ to full FIFO!");
            end

            if (deq_en && ! notEmpty)
            begin
                error <= 1'b1;
                $fatal(2, "** ERROR ** %m: DEQ from empty FIFO!");
            end
        end
    end

    // Update count of live values
    always_ff @(posedge clk)
    begin
        valid_cnt <= valid_cnt_next;
        notFull <= (valid_cnt_next != t_counter'(N_ENTRIES)) && ! error;
        almostFull <= (valid_cnt_next >= t_counter'(N_ENTRIES - THRESHOLD)) || error;
        notEmpty <= (valid_cnt_next != t_counter'(0)) && ! error;

        if (!reset_n)
        begin
            valid_cnt <= t_counter'(0);
            notEmpty <= 1'b0;
            notFull <= 1'b0;
            almostFull <= 1'b1;
        end
    end

    always_comb
    begin
        valid_cnt_next = valid_cnt;

        if (deq_en && ! enq_en)
        begin
            valid_cnt_next = valid_cnt_next - t_counter'(1);
        end
        else if (enq_en && ! deq_en)
        begin
            valid_cnt_next = valid_cnt_next + t_counter'(1);
        end
    end

endmodule // ofs_plat_prim_fifo_lutram_ctrl
