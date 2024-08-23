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
    // Virtual channel info for multiplexed streams. E.g., multiple PCIe VFs
    // in a single interface. When the PIM-generated host channel mapping to
    // memory mapped interfaces remains multiplexed, routing information is
    // added to the user field.
    //
    // The Avalon-MM interface exposed by the PIM to AFUs is supposed to be independent
    // of the protocol of the actual device in the FIM. Virtual channels
    // for a multiplexed channel are necessarily protocol-specific. As a compromise,
    // we define a dense vchan ID. The platform-specific code in the PIM manages
    // the mapping from vchan to device mapping, e.g. to PF/VF.
    //
    // Because the interface here is device independent, the size of the vchan
    // ID is fixed. The current value, 11, matches the maximum PCIe VF.
    localparam HC_AVALON_UFLAG_VCHAN_WIDTH = 11;
    typedef logic [HC_AVALON_UFLAG_VCHAN_WIDTH-1:0] t_hc_avalon_user_vchan;

    // Full user flags struct for use when vchan is added to the user field.
    // The low bits in base are the same as normal user flags. This struct
    // is larger than the default user field size, so AFUs that enable
    // multiplexed memory mapped interfaces must ensure the instantiated
    // interfaces specify proper user field width.
    typedef struct packed {
        // Virtual channel for multiplexed streams such as multiple PCIe PF/VFs
        t_hc_avalon_user_vchan vchan;

        // Base flags, e.g. fence.
        t_hc_avalon_user_flags base;
    } t_hc_avalon_user_flags_with_vchan;
    localparam HC_AVALON_UFLAG_WITH_VCHAN_WIDTH = $bits(t_hc_avalon_user_flags_with_vchan);


    //
    // Flags on MMIO user fields
    //

    // Currently there are no base MMIO flags. Data structure defined as
    // a placeholder.
    typedef struct packed {
        logic reserved;
    } t_hc_avalon_mmio_user_flags;
    localparam HC_AVALON_MMIO_UFLAG_WIDTH = $bits(t_hc_avalon_user_flags);

    typedef struct packed {
        // Virtual channel for multiplexed streams such as multiple PCIe PF/VFs
        t_hc_avalon_user_vchan vchan;
        t_hc_avalon_mmio_user_flags base;
    } t_hc_avalon_mmio_user_flags_with_vchan;
    localparam HC_AVALON_MMIO_UFLAG_WITH_VCHAN_WIDTH = $bits(t_hc_avalon_mmio_user_flags_with_vchan);

endpackage // ofs_plat_host_chan_avalon_mem_pkg
