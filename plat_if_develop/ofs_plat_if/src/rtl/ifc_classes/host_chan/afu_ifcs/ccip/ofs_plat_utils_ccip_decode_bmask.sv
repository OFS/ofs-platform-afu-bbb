// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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
