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
    // *** t_hc_avalon_user_flags_enum and t_hc_avalon_user_flags must match.
    // *** The enum was defined in the PIM long before the struct and
    // *** remains for backward compatibility.
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

    typedef struct packed {
        // Flags -- see t_hc_avalon_user_flags_enum above
        logic interrupt;
        logic fence;
        logic no_reply;
    } t_hc_avalon_user_flags;
    localparam HC_AVALON_UFLAG_WIDTH = $bits(t_hc_avalon_user_flags);


    //
    // Message routing info for multiplexed streams. E.g., multiple PCIe VFs
    // in a single interface. When the PIM-generated host channel mapping to
    // memory mapped interfaces remains multiplexed, routing information is
    // added to the user field.
    //
    // The Avalon-MM interface exposed by the PIM to AFUs is supposed to be independent
    // of the protocol of the actual device in the FIM. Routing information
    // for a multiplexed channel is necessarily protocol-specific. As a compromise,
    // we define a union of all supported routing tags so that the data structure
    // remains the same everywhere. The only current routing info is PCIe PF/VFs.
    //
    typedef struct packed {
        logic vf_active;
        logic [10:0] vf_num;
        logic [2:0] pf_num;
    } t_hc_avalon_user_routing_pcie;

    typedef union packed {
        t_hc_avalon_user_routing_pcie pcie;
    } t_hc_avalon_user_routing;

    // Full user flags struct for use when routing is added to the user field.
    // The low bits in base are the same as normal user flags. This struct
    // is larger than the default user field size, so AFUs that enable
    // multiplexed memory mapped interfaces must ensure the instantiated
    // interfaces specify proper user field width.
    typedef struct packed {
        // Routing info for multiplexed streams such as multiple PCIe PF/VFs
        t_hc_avalon_user_routing routing;

        // Base flags, e.g. fence.
        t_hc_avalon_user_flags base;
    } t_hc_avalon_user_flags_with_routing;

endpackage // ofs_plat_host_chan_avalon_mem_pkg
