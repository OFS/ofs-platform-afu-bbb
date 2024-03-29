// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

package ofs_plat_host_chan_axi_mem_pkg;

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
        HC_AXI_UFLAG_NO_REPLY = 0,

        // AW (write address) stream only. Inject a write fence. Packet
        // AWLEN must be 0. AWADDR is ignored. The source must still generate
        // a corresponding W packet to avoid confusing AXI routing networks.
        HC_AXI_UFLAG_FENCE = 1,

        // AW stream only. Trigger an interrupt. The vector is indicated by
        // low bits of the AWADDR. AWLEN must be 0 and the source must still
        // generate a W packet.
        HC_AXI_UFLAG_INTERRUPT = 2,

        // The atomic flag is mainly internal to the PIM, used to associate
        // atomic requests on AW with read responses. AFUs should always set
        // the flag to 0. The PIM guarantees that the atomic flag will be set
        // on the R and B channels in response to atomic requests.
        // AFUs are permitted to depend on the flag, though using the AXI-MM
        // ID tags is the AXI standard conforming mechanism.
        HC_AXI_UFLAG_ATOMIC = 3
    } t_hc_axi_user_flags_enum;

    // Maximum value of a HC_AXI_UFLAG
    localparam HC_AXI_UFLAG_MAX = HC_AXI_UFLAG_ATOMIC;

    localparam HC_AXI_UFLAG_WIDTH = HC_AXI_UFLAG_MAX + 1;
    typedef logic [HC_AXI_UFLAG_WIDTH-1 : 0] t_hc_axi_user_flags;

endpackage // ofs_plat_host_chan_axi_mem_pkg
