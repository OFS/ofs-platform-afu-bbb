// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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
