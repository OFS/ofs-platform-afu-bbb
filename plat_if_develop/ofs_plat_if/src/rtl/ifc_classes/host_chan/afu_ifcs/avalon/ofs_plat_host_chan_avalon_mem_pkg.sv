// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

package ofs_plat_host_chan_avalon_mem_pkg;

    //
    // Modifiers to memory write and read requests.
    //
    // User bits can indicate special-case commands. The values of
    // individual commands may change over time as Avalon standards evolve.
    // Portable code should use the enumeration.
    //
    typedef enum
    {
        // NO_REPLY is used inside the PIM to squash extra read or write
        // responses when AFU-sized bursts are broken into FIU-sized bursts
        // by the PIM.
        HC_AVALON_UFLAG_NO_REPLY = 0,

        // Write request stream only. Inject a write fence. Packet
        // length must be 1. Address is ignored.
        HC_AVALON_UFLAG_FENCE = 1,

        // Write stream only. Trigger an interrupt. The vector is indicated by
        // low bits of the address. Packet length must be 1.
        HC_AVALON_UFLAG_INTERRUPT = 2
    } t_hc_avalon_user_flags_enum;

    // Maximum value of a HC_AVALON_UFLAG
    localparam HC_AVALON_UFLAG_MAX = HC_AVALON_UFLAG_INTERRUPT;

    localparam HC_AVALON_UFLAG_WIDTH = HC_AVALON_UFLAG_MAX + 1;
    typedef logic [HC_AVALON_UFLAG_WIDTH-1 : 0] t_hc_avalon_user_flags;

endpackage // ofs_plat_host_chan_avalon_mem_pkg
