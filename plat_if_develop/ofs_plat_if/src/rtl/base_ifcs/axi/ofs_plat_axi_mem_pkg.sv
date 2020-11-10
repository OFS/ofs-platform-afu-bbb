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
    //   0b01exxx    AtomicStore
    //   0b10exxx    AtomicLoad
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

endpackage // ofs_plat_axi_mem_pkg
