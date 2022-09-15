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
// Map MMIO write data to a target write bus (DATA_WIDTH) that may be larger
// than the dynamic MMIO write payload (byte_count). Remapping is handled
// by replicating the data and generating a mask to indicate the location
// of the data in the bus.
//
module ofs_plat_host_chan_mmio_wr_data_comb
  #(
    parameter DATA_WIDTH = 64
    )
   (
    // Address and size of write data. Only the low bits of the address
    // will be used in order to compute a write byte mask.
    input  logic [63:0] byte_addr,
    input  logic [11:0] byte_count,
    input  logic [DATA_WIDTH-1:0] payload_in,

    output logic [DATA_WIDTH-1:0] payload_out,
    output logic [DATA_WIDTH/8-1:0] byte_mask
    );

    typedef logic [DATA_WIDTH-1:0] t_payload;

    // Replicate chunks of size "n_bytes" into a 512 bit line. MMIO up to 512 bits
    // is supported. MMIO operations needing replication into smaller lines can
    // just truncate the result and synthesis will drop the unused part.
    function automatic logic [511:0] replicate_chunks(
        logic [11:0] n_bytes,
        logic [63:0] byte_addr,
        logic [511:0] d_in
        );

        logic [511:0] d_out;

        if (n_bytes <= 4)
            d_out = {16{d_in[31:0]}};
        else if (n_bytes <= 8)
            // Special case for an 8 byte write to an address that is aligned
            // only to 4 bytes. Technically, this is not supported, but there
            // are some errant tests that do this. We don't waste area
            // on any sizes larger than 8 bytes -- just this case.
            d_out = byte_addr[2] ? {16{d_in[31:0]}} : {8{d_in[63:0]}};
        else if (n_bytes <= 16)
            d_out = {4{d_in[127:0]}};
        else if (n_bytes <= 32)
            d_out = {2{d_in[255:0]}};
        else
            d_out = d_in;

        return d_out;
    endfunction // mmio_replicate_chunks

    // Replicate small write data across the entire data width
    assign payload_out = t_payload'(replicate_chunks(byte_count, byte_addr,
                                                     { '0, payload_in }));

    // First stage of byte mask generation: generate a DWORD-level mask
    // (PCIe's smallest object).
    localparam NUM_DWORDS = DATA_WIDTH / 32;
    localparam NUM_DWORD_IDX_BITS = $clog2(NUM_DWORDS);
    typedef logic [NUM_DWORD_IDX_BITS-1 : 0] t_dword_idx;

    logic [NUM_DWORDS-1 : 0] dw_mask;
    assign dw_mask =
        ~(~NUM_DWORDS'(0) << byte_count[2 +: NUM_DWORD_IDX_BITS+1]) << byte_addr[2 +: NUM_DWORD_IDX_BITS];

    // Turn the DWORD-level mask into a byte mask.
    always_comb
    begin
        for (int dw = 0; dw < NUM_DWORDS; dw = dw + 1)
        begin
            byte_mask[dw*4 +: 4] = {4{dw_mask[dw]}};
        end
    end

endmodule // ofs_plat_host_chan_mmio_wr_data_comb
