// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Generic ready/enable pipeline stage. This implementation shares the same
// interface as the systolic version (ofs_plat_prim_ready_enable_reg), but
// internally adds a FIFO. This adds a register between ready_from_dst and
// ready_to_src, thus breaking control flow into shorter and simpler logic
// at the expense of area.
//

module ofs_plat_prim_ready_enable_skid
  #(
    parameter N_DATA_BITS = 32
    )
   (
    input  logic clk,
    input  logic reset_n,

    input  logic enable_from_src,
    input  logic [N_DATA_BITS-1 : 0] data_from_src,
    output logic ready_to_src,

    output logic enable_to_dst,
    output logic [N_DATA_BITS-1 : 0] data_to_dst,
    input  logic ready_from_dst
    );

    //
    // Using the FIFO2 here generates logic that is essentially equivalent
    // to the Quartus Avalon bridge's management of the request bus.
    //
    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(N_DATA_BITS)
        )
      f
       (
        .clk,
        .reset_n,

        .enq_data(data_from_src),
        .enq_en(enable_from_src && ready_to_src),
        .notFull(ready_to_src),

        .first(data_to_dst),
        .deq_en(enable_to_dst && ready_from_dst),
        .notEmpty(enable_to_dst)
        );

endmodule // ofs_plat_prim_ready_enable_skid
