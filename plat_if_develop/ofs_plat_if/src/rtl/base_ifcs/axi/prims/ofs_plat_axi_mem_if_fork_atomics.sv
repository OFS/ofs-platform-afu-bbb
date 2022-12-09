// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Fork atomic update requests into two requests: the original on the write
// request channel and a copy on the read request channel. The read request
// copy is just a placeholder, used to allocate ROB slots and tags internal
// to the PIM. These slots will be used when passing the read response from
// the atomic update back to the AFU.
//
module ofs_plat_axi_mem_if_fork_atomics
   (
    ofs_plat_axi_mem_if.to_sink mem_sink,
    ofs_plat_axi_mem_if.to_source mem_source
    );

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_IF_CHECK_PARAMS_MATCH(mem_sink, mem_source)
    // synthesis translate_on

    wire clk = mem_sink.clk;
    wire reset_n = mem_sink.reset_n;

    // Response channels and write data are simple connections.
    assign mem_sink.w = mem_source.w;
    assign mem_sink.wvalid = mem_source.wvalid;
    assign mem_source.wready = mem_sink.wready;

    assign mem_source.b = mem_sink.b;
    assign mem_source.bvalid = mem_sink.bvalid;
    assign mem_sink.bready = mem_source.bready;

    assign mem_source.r = mem_sink.r;
    assign mem_source.rvalid = mem_sink.rvalid;
    assign mem_sink.rready = mem_source.rready;

    //
    // Replicate atomic AW requests into a FIFO, which will feed into AR.
    //
    localparam WID_WIDTH = mem_sink.WID_WIDTH_;
    localparam ADDR_WIDTH = mem_sink.ADDR_WIDTH_;

    typedef struct packed {
        logic [WID_WIDTH-1 : 0] id;
        logic [ADDR_WIDTH-1 : 0] addr;
        ofs_plat_axi_mem_pkg::t_axi_log2_beat_size size;
    } t_atomic_req;

    t_atomic_req areq_in, areq_out;
    logic areq_notFull, areq_notEmpty;

    // Only treat well-formatted requests as atomic. Obviously this doesn't check
    // everything, but it's a start.
    wire mem_source_is_atomic = mem_source.aw.atop[5] &&
                                (mem_source.aw.len == 0) &&
                                ((mem_source.aw.size == 3'b010) ||
                                 (mem_source.aw.size == 3'b011) ||
                                 (mem_source.aw.size == 3'b100));

    always_comb
    begin
        areq_in.id = mem_source.aw.id;
        areq_in.addr = mem_source.aw.addr;
        areq_in.size = mem_source.aw.size;
    end

    // Avoid starving both reads and forked atomic requests
    logic arb_allow_rd;
    logic arb_allow_atomic;
    logic arb_last_was_atomic;

    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS($bits(t_atomic_req))
        )
      areq_fifo
       (
        .clk,
        .reset_n,

        .enq_data(areq_in),
        .enq_en(mem_source.awvalid && mem_source.awready && mem_source_is_atomic),
        .notFull(areq_notFull),

        .first(areq_out),
        .deq_en(arb_allow_atomic && mem_sink.arready),
        .notEmpty(areq_notEmpty)
        );

    // Block AW traffic when the FIFO is full
    assign mem_source.awready = mem_sink.awready && areq_notFull;
    assign mem_sink.awvalid = mem_source.awvalid && areq_notFull;
    // Set the atomic flag on AW for valid requests
    always_comb
    begin
        mem_sink.aw = mem_source.aw;
        mem_sink.aw.user[ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_ATOMIC] = mem_source_is_atomic;
    end

    // Arbitration between reads and fored atomic requests
    assign arb_allow_rd = !areq_notEmpty || arb_last_was_atomic;
    assign arb_allow_atomic = ~arb_allow_rd;

    always_ff @(posedge clk)
    begin
        arb_last_was_atomic <= arb_allow_atomic && mem_sink.arready;
        if (!reset_n)
        begin
            arb_last_was_atomic <= 1'b0;
        end
    end

    // Block AR traffic when a forked atomic needs the path
    assign mem_source.arready = mem_sink.arready && arb_allow_rd;
    assign mem_sink.arvalid = mem_source.arvalid || arb_allow_atomic;

    always_comb
    begin
        if (arb_allow_rd)
        begin
            // Normal read request
            mem_sink.ar = mem_source.ar;
            mem_sink.ar.user[ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_ATOMIC] = 1'b0;
        end
        else
        begin
            // Synthesized forked atomic read request
            mem_sink.ar = '0;
            mem_sink.ar.id = areq_out.id;
            mem_sink.ar.addr = areq_out.addr;
            mem_sink.ar.size = areq_out.size;
            // Set a flag indicating this is a dummy atomic read
            mem_sink.ar.user[ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_ATOMIC] = 1'b1;
        end
    end

    // synthesis translate_off
    always_ff @(negedge clk)
    begin
        if (reset_n && mem_source.awvalid && mem_source.awready)
        begin
            assert ((mem_source.aw.atop == 0) || mem_source_is_atomic) else
              $fatal(2, "** ERROR ** %m: mem_source AW atomic is set but request is not a valid format!");
        end
    end
    // synthesis translate_on

endmodule // ofs_plat_axi_mem_if_fork_atomics
