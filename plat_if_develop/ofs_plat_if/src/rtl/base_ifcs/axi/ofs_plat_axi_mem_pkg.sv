// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// AXI memory interface types.
//

package ofs_plat_axi_mem_pkg;

    // Encoded byte size of data in one beat of a burst:
    //   0b000: 1
    //   0b001: 2
    //   0b010: 4
    //   0b011: 8
    //   0b100: 16
    //   0b101: 32
    //   0b110: 64
    //   0b111: 128
    typedef logic [2:0] t_axi_log2_beat_size;

    function automatic logic [15:0] beat_size_to_byte_mask(t_axi_log2_beat_size size);
        logic [15:0] mask;
        case (size)
          3'b000: mask = 'h1;
          3'b001: mask = 'h3;
          3'b010: mask = 'hf;
          3'b011: mask = 'hff;
          3'b100: mask = 'hffff;
          3'b101: mask = 'hffffffff;
          3'b110: mask = 'hffffffffffffffff;
          3'b111: mask = 'hffffffffffffffffffffffffffffffff;
        endcase

        return mask;
    endfunction // beat_size_to_byte_mask

    // Burst type:
    //   0b00: FIXED
    //   0b01: INCR
    //   0b10: WRAP
    //   0b11: Reserved
    typedef logic [1:0] t_axi_burst_type;

    typedef logic t_axi_lock;

    // Memory type encoding
    //   ARCACHE[3:0] AWCACHE[3:0] Memory type
    //   0000         0000         Device Non-bufferable
    //   0001         0001         Device Bufferable
    //   0010         0010         Normal Non-cacheable Non-bufferable
    //   0011         0011         Normal Non-cacheable Bufferable
    //   1010         0110         Write-through No-allocate
    //   1110 (0110)  0110         Write-through Read-allocate
    //   1010         1110 (1010)  Write-through Write-allocate
    //   1110         1110         Write-through Read and Write-allocate
    //   1011         0111         Write-back No-allocate
    //   1111 (0111)  0111         Write-back Read-allocate
    //   1011         1111 (1011)  Write-back Write-allocate
    //   1111         1111         Write-back Read and Write-allocate
    typedef logic [3:0] t_axi_memory_type;

    // Protection encoding
    //   AxPROT Value Function
    //   [0]    0     Unprivileged access
    //          1     Privileged access
    //   [1]    0     Secure access
    //          1     Non-secure access
    //   [2]    0     Data access
    //          1     Instruction access
    typedef logic [2:0] t_axi_prot;

    // QoS -- 0 default
    typedef logic [3:0] t_axi_qos;

    // Address space region (0 default)
    typedef logic [3:0] t_axi_region;

    // Read or write response
    //   0b00: OKAY
    //   0b01: EXOKAY -- Exclusive access successful
    //   0b10: SLVERR -- Sink returns error
    //   0b11: DECERR -- Decode error (no sink?)
    typedef logic [1:0] t_axi_resp;

    // Atomic requests (AXI5 only)
    //   AWATOP[5:0] Description
    //   0b000000    Non-atomic operation
    //   0b010xxx    AtomicStore
    //   0b100xxx    AtomicLoad
    //   0b110000    AtomicSwap
    //   0b110001    AtomicCompare
    //
    // Encodings for low order bits of store and load:
    //   AWATOP[2:0] Operation Description
    //   0b000       ADD       Add
    //   0b001       CLR       Bit clear
    //   0b010       EOR       Exclusive OR
    //   0b011       SET       Bit set
    //   0b100       SMAX      Signed maximum
    //   0b101       SMIN      Signed minimum
    //   0b110       UMAX      Unsigned maximum
    //   0b111       UMIN      Unsigned minimum
    typedef logic [5:0] t_axi_atomic;

    // Some convenience values, matching PCIe atomics
    localparam t_axi_atomic ATOMIC_ADD   = 6'b100000;
    localparam t_axi_atomic ATOMIC_SWAP  = 6'b110000;
    localparam t_axi_atomic ATOMIC_CAS   = 6'b110001;

endpackage // ofs_plat_axi_mem_pkg
