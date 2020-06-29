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
// Generic ready/enable pipeline register. This implementation is a simple,
// systolic pipeline with control shared by all registers in a chain.
// For a version that breaks apart control flow into separate stages
// see ofs_plat_prim_ready_enable_skid().
//

module ofs_plat_prim_ready_enable_reg
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

    // This primitive can only implement a systolic pipeline. The ready
    // signal controls the entire pipeline.
    assign ready_to_src = ready_from_dst;

    always_ff @(posedge clk)
    begin
        if (ready_from_dst)
        begin
            enable_to_dst <= enable_from_src;
            data_to_dst <= data_from_src;
        end

        if (!reset_n)
        begin
            enable_to_dst <= 1'b0;
        end
    end

endmodule // ofs_plat_prim_ready_enable_reg
