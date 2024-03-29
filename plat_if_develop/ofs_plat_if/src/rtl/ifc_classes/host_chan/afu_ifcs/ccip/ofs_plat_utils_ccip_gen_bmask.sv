// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Convert a CCI-P byte range (start/end) to a byte mask, which is used for
// Avalon and AXI byte write control.
//
// The output is combinational.
//
module ofs_plat_utils_ccip_gen_bmask
   (
    input  t_ccip_clByteIdx byte_start,
    // The sum of byte_start and byte_len, thus the index of the first
    // byte beyond the mask. This encoding avoids having to subtract
    // one from the sum.
    input  t_ccip_clByteIdx byte_start_plus_len,

    // Mask matching start/len, generated combinationally from the
    // inputs.
    output logic [CCIP_CLDATA_BYTE_WIDTH-1 : 0] bmask
    );

    typedef logic [CCIP_CLDATA_BYTE_WIDTH-1 : 0] t_bytemask;

    function automatic t_bytemask decodeMaskStart(t_ccip_clByteIdx start_idx);
        t_bytemask masks[CCIP_CLDATA_BYTE_WIDTH];

        // Build a lookup table, with 1's in all bits idx and higher.
        masks[0] = ~t_bytemask'(0);
        for (int i = 1; i < CCIP_CLDATA_BYTE_WIDTH; i = i + 1)
        begin
            // Shift in another 0
            masks[i] = masks[i-1] << 1;
        end

        return masks[start_idx];
    endfunction

    //
    // Generate a mask selecting all bytes in a line below end_idx. The range does not
    // include end_idx, which avoids having to subtract 1 when computing end_idx
    // from the sum of the start index and length.
    //
    function automatic t_bytemask decodeMaskEnd(t_ccip_clByteIdx end_idx);
        t_bytemask masks[CCIP_CLDATA_BYTE_WIDTH];

        // Build a lookup table, with 0's in all bits above idx. The table is rotated
        // by 1 since the mask does not include the bit at end_idx.
        masks[1] = 1;
        for (int i = 2; i < CCIP_CLDATA_BYTE_WIDTH; i = i + 1)
        begin
            // Shift in another 1
            masks[i] = (masks[i-1] << 1) | 1'b1;
        end
        masks[0] = ~t_bytemask'(0);

        return masks[end_idx];
    endfunction

    assign bmask = decodeMaskStart(byte_start) &
                   decodeMaskEnd(byte_start_plus_len);

endmodule // ofs_plat_utils_ccip_gen_bmask
