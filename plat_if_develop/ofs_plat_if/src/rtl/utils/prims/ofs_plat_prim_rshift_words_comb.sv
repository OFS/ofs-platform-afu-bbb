// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


//
// Combinational, variable shift N words right. The shift is organized as
// a cascade of binary decisions, acting on each bit in the shift count
// independently. The multiplexing depth is log2(DATA_WIDTH / WORD_WIDTH),
// e.g. depth 4 for 512 bit data and 32 bit words.
//
// The circuit is surprisingly fast. A 512 x 16 shifter (one deeper than
// the typical 512 x 32 used for shifting PCIe DWORDs) can achieve nearly
// 500 MHz on Stratix 10.
//
module ofs_plat_prim_rshift_words_comb
  #(
    parameter DATA_WIDTH = 512,
    parameter WORD_WIDTH = 32
    )
   (
    input  logic [DATA_WIDTH-1 : 0] d_in,
    input  logic [$clog2(DATA_WIDTH / WORD_WIDTH)-1 : 0] rshift_cnt,
    output logic [DATA_WIDTH-1 : 0] d_out
    );

    localparam NUM_WORDS = DATA_WIDTH / WORD_WIDTH;
    localparam WORD_IDX_WIDTH = $clog2(NUM_WORDS);

    typedef logic [NUM_WORDS-1:0][WORD_WIDTH-1:0] t_word_vec;

    // Incoming data to wv[WORD_IDX_WIDTH]. Outgoing shifted data on wv[0].
    t_word_vec wv[WORD_IDX_WIDTH + 1];
    assign d_out = wv[0];

    always_comb
    begin
        wv[WORD_IDX_WIDTH] = d_in;

        // For each bit in the shift count (starting with the high one)
        for (int b = WORD_IDX_WIDTH-1, chunk = 0; b >= 0; b = b - 1)
        begin
            // Shift chunks, sized corresponding to the selected bit.
            chunk = (1 << b);
            for (int i = 0; i < NUM_WORDS - chunk; i = i + 1)
            begin
                // Binary decision - When shift bit is 1, take the upper chunk.
                // When shift bit is 0, keep the chunk in its current position.
                wv[b][i] = (rshift_cnt[b] ? wv[b+1][i+chunk] : wv[b+1][i]);
            end

            // The end of the array, corresponding to the last chunk,
            // has no source of data if the shift bit is 1. The data would
            // come from outside the array. If the shift bit is 0 then we
            // need the original data. We only have to consider the case
            // of the shift bit being 0 here.
            for (int i = NUM_WORDS - chunk; i < NUM_WORDS; i = i + 1)
            begin
                wv[b][i] = wv[b+1][i];
            end
        end
    end

endmodule
