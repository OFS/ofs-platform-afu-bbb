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
// Synthetic data generator and tester. The same algorithms are implemented
// in software in test_data.c.
//

//
// Generate a line of data. The next line is a function of the previous
// line and a seed.
//
module test_data_gen
  #(
    // Data width (bits) must be a power of 2 and at least 64.
    parameter DATA_WIDTH = 512
    )
   (
    input  logic clk,
    input  logic reset_n,

    input  logic gen_next,
    input  logic [63:0] seed,

    output logic [DATA_WIDTH-1 : 0] data
    );

    typedef logic [DATA_WIDTH-1 : 0] t_data;

    localparam [511:0] DATA_INIT = { 64'h8644554624594bbf, 64'hb173761f0b5a083b,
                                     64'h76655f3e9ba84438, 64'hafcc6ba3db67f2b3,
                                     64'h33b23fb3ab3c4277, 64'h8519a51b2767a2fa,
                                     64'h54de0dc97b564cbf, 64'h860761722b164a00 };

    function automatic logic [63:0] rotateleft(logic [63:0] v, int r);
        logic [127:0] t = { v, v } << r;
        return t[127:64];
    endfunction

    always_ff @(posedge clk)
    begin
        if (gen_next)
        begin
            // Generate new data for next line using a function that can be
            // replicated for comparison in software.
            for (int i = 0; i < $bits(t_data); i = i + 64)
            begin
                // Rotate each 64 bit word one byte left and XOR the seed.
                // The seed is rotated 1 bit per entry so it is a different
                // value in each word.
                data[i +: 64] <= { data[i +: 56], data[i+56 +: 8] } ^
                                 rotateleft(seed, i / 64);
            end
        end

        if (!reset_n)
        begin
            // Replicate DATA_INIT into data and XOR rotations of the seed
            // into each 64-bit word.
            for (int i = 0; i < $bits(t_data); i = i + 64)
            begin
                data[i +: 64] <= DATA_INIT[i % 512 +: 64] ^
                                 rotateleft(seed, i / 64);
            end
        end
    end

endmodule // test_data_gen



//
// Test received data by hashing the data. Since there is a software
// equivalent of both test_data_gen() above and this module, it is
// possible to synthesize data in both software and hardware and
// compare the hashed result.
//
module test_data_chk
  #(
    // Data width (bits) must be a power of 2 and at least 64.
    parameter DATA_WIDTH = 512
    )
   (
    input  logic clk,
    input  logic reset_n,

    input  logic new_data_en,
    input  logic [DATA_WIDTH-1 : 0] new_data,

    output logic [63:0] hash
    );

    //
    // Include each new_data in a set of hash buckets for validating
    // correctness. Register the inputs and outputs for timing.
    // We assume that whatever is reading the hash will wait for
    // the system to be quiet.
    //
    localparam HASH_BUCKETS_PER_LINE = DATA_WIDTH / 32;
    logic hash32_en;
    logic [HASH_BUCKETS_PER_LINE-1 : 0][31:0] hash32_value;
    logic [HASH_BUCKETS_PER_LINE-1 : 0][31:0] hash32_new_data;

    always_ff @(posedge clk)
    begin
        hash32_en <= new_data_en;
        hash32_new_data <= new_data;
    end

    genvar b;
    generate
        for (b = 0; b < HASH_BUCKETS_PER_LINE; b = b + 1)
        begin : hb
            hash32 hash_read_resps
               (
                .clk,
                .reset_n,
                .en(hash32_en),
                .new_data(hash32_new_data[b]),
                .value(hash32_value[b])
                );
        end
    endgenerate


    //
    // XOR all the hashes down to a single 64 bit value.
    //
    typedef logic [(HASH_BUCKETS_PER_LINE/2)-1 : 0][31:0] t_hash_half;

    function automatic logic [31:0] test_reduce_hashes(t_hash_half hash_in);
        logic [31:0] hash;

        // XOR together all the buckets.
        hash = hash_in[0];
        for (int i = 1; i < HASH_BUCKETS_PER_LINE/2; i = i + 1)
        begin
            hash = hash ^ hash_in[i];
        end

        return hash;
    endfunction // test_reduce_hashes

    (* noprune *) logic [31:0] test_data_hash_reduce_regs[2];

    always_ff @(posedge clk)
    begin
        test_data_hash_reduce_regs[0] <=
            test_reduce_hashes(hash32_value[(HASH_BUCKETS_PER_LINE / 2) - 1 : 0]);

        test_data_hash_reduce_regs[1] <=
            test_reduce_hashes(hash32_value[HASH_BUCKETS_PER_LINE - 1 : HASH_BUCKETS_PER_LINE / 2]);
    end

    // Return the pair of reduced 32-bit XOR registers as one 64 bit value
    always_ff @(posedge clk)
    begin
        hash <= { test_data_hash_reduce_regs[1], test_data_hash_reduce_regs[0] };
    end

endmodule // test_data_chk
