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

package ofs_plat_local_mem_axi_mem_pkg;

    //
    // Modifiers to memory write and read requests.
    //
    // User bits can indicate special-case commands. The values of
    // individual commands may change over time as AXI standards evolve.
    // Portable code should use the enumeration.
    //
    typedef enum
    {
        // NO_REPLY is used inside the PIM to squash extra R or B channel
        // responses when AFU-sized bursts are broken into FIU-sized bursts
        // by the PIM.
        LM_AXI_UFLAG_NO_REPLY = 0
    } t_lm_axi_user_flags_enum;

    // Maximum value of an LM_AXI_UFLAG
    localparam LM_AXI_UFLAG_MAX = LM_AXI_UFLAG_NO_REPLY;

    localparam LM_AXI_UFLAG_WIDTH = LM_AXI_UFLAG_MAX + 1;
    typedef logic [LM_AXI_UFLAG_WIDTH-1 : 0] t_lm_axi_user_flags;

endpackage // ofs_plat_local_mem_axi_mem_pkg
