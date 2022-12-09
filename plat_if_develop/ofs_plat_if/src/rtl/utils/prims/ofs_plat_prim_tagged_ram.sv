// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Store state in a RAM, with the index allocated by an internal tag generator.
// The write operation allocates a tag and a read deallocates it.
//

module ofs_plat_prim_tagged_ram
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,
    parameter N_OUTPUT_REG_STAGES = 1
    )
   (
    input  logic clk,
    input  logic reset_n,

    input  logic alloc_en,
    input  logic [N_DATA_BITS-1 : 0] allocData,      // Save meta-data for new entry
    output logic notFull,
    output logic [$clog2(N_ENTRIES)-1 : 0] allocIdx, // Index of new entry

    input  logic rd_en,
    input  logic [$clog2(N_ENTRIES)-1 : 0] rdIdx,    // Index of entry to read
    // Data arrives N_OUTPUT_REG_STAGES + 1 cycles after rd_en is set
    output logic [N_DATA_BITS-1 : 0] first,
    output logic valid,

    input  logic deq_en,
    input  logic [$clog2(N_ENTRIES)-1 : 0] deqIdx    // Index of entry to deallocate
    );


    // T2_valid is implemented in this module for convenience. It
    // fires 2 cycles after rd_en, when first arrives.
    logic [N_OUTPUT_REG_STAGES : 0] rd_rsp_valid;
    assign valid = rd_rsp_valid[N_OUTPUT_REG_STAGES];

    always_ff @(posedge clk)
    begin
        rd_rsp_valid[0] <= rd_en;
        for (int i = 1; i <= N_OUTPUT_REG_STAGES; i = i + 1)
        begin
            rd_rsp_valid[i] <= rd_rsp_valid[i-1];
        end
    end


    //
    // Tags
    //
    ofs_plat_prim_uid
      #(
        .N_ENTRIES(N_ENTRIES)
        )
      tags
       (
        .clk,
        .reset_n,

        .alloc(alloc_en),
        .alloc_ready(notFull),
        .alloc_uid(allocIdx),

        .free(deq_en),
        .free_uid(deqIdx)
        );


    //
    // Data
    //
    ofs_plat_prim_ram_simple
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(N_DATA_BITS),
        .N_OUTPUT_REG_STAGES(N_OUTPUT_REG_STAGES),
        .REGISTER_WRITES(1),
        .BYPASS_REGISTERED_WRITES(0)
        )
      memData
       (
        .clk,

        .waddr(allocIdx),
        .wen(alloc_en),
        .wdata(allocData),

        .raddr(rdIdx),
        .rdata(first)
        );

endmodule // ofs_plat_prim_tagged_ram
