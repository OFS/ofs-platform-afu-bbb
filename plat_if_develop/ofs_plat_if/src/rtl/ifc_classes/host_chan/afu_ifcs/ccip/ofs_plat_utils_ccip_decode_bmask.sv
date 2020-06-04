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
// Decode byte mask (from Avalon or AXI) into a CCI-P masked write range.
//
// The output is available on the second cycle after the input.
//

`include "ofs_plat_if.vh"

module ofs_plat_utils_ccip_decode_bmask
   (
    input  logic clk,
    input  logic reset_n,

    input  logic [CCIP_CLDATA_BYTE_WIDTH-1 : 0] bmask,

    output t_ccip_mem_access_mode T2_wr_mode,
    output t_ccip_clByteIdx T2_byte_start,
    output t_ccip_clByteIdx T2_byte_len
    );

    t_ccip_mem_access_mode wr_mode;
    t_ccip_clByteIdx byte_start;
    t_ccip_clByteIdx byte_end;

    // Stage 1: Convert mask for writes into byte_start/byte_len
    always_ff @(posedge clk)
    begin
        // Masked write will have a zero in either the low or high bit
        wr_mode <= (bmask[63] & bmask[0]) ? eMOD_CL : eMOD_BYTE;

        // First byte to write
        for (int i = 0; i <= 63; i = i + 1)
        begin
            if (bmask[i])
            begin
                byte_start <= t_ccip_clByteIdx'(i);
                break;
            end
        end

        // Last byte to write
        for (int i = 0; i <= 63; i = i + 1)
        begin
            if (bmask[i])
            begin
                byte_end <= t_ccip_clByteIdx'(i);
            end
        end
    end

    // Stage 2: Compute length and generate output
    always_ff @(posedge clk)
    begin
        T2_wr_mode <= wr_mode;
        T2_byte_start <= byte_start;
        T2_byte_len <= byte_end - byte_start + 1;
    end

endmodule // ofs_plat_utils_ccip_decode_bmask
