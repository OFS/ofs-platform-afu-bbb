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

    typedef logic [NUM_WORDS-1:0][31:0] t_word_vec;

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
