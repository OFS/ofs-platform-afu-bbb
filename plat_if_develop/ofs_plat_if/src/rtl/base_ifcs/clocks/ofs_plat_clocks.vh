// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Standard clock types
//

`ifndef __OFS_PLAT_CLOCKS_VH__
`define __OFS_PLAT_CLOCKS_VH__

`include "ofs_plat_if.vh"

typedef struct packed
{
    logic clk;
    logic reset_n;
}
t_ofs_plat_clock_reset_pair;

//
// Clocks provided for each host channel port. All conforming platforms
// provide at least 5 primary clocks: pClk, pClkDiv2, pClkDiv4, uClk_usr
// and uClk_usrDiv2. Divided clocks are all aligned to their primary clocks.
//
// Each clock has an associated reset that is synchronous in the clock's
// domain. While an AFU could generate these resets, the platform provides
// them.
//
// Resets are active low.
//
typedef struct packed
{
    t_ofs_plat_clock_reset_pair pClk;
    t_ofs_plat_clock_reset_pair pClkDiv2;
    t_ofs_plat_clock_reset_pair pClkDiv4;
    t_ofs_plat_clock_reset_pair uClk_usr;
    t_ofs_plat_clock_reset_pair uClk_usrDiv2;
}
t_ofs_plat_std_afu_clocks;

//
//
typedef struct packed
{
    // A normal FIM configuration provides an instance of the standard
    // AFU clocks with reset controlled by soft reset for each host channel
    // port. A configuration with multiple PFs or VFs, and therefore multiple
    // host channels, will normally have separate soft resets for each PF/VF.
    // The index of ports[] here matches the index of host channel ports.
    //
    // There is typically a single uClk, shared by all ports. Thus all clocks
    // will be the same for all indices in ports, but the resets will differ
    // due to separate soft reset control of each port.
    t_ofs_plat_std_afu_clocks [`OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS - 1 : 0] ports;

    // These are provided for legacy AFU support. Before multiple PFs and VFs
    // where supported, there was a single host channel. The resets below
    // are identical to the resets in ports[0] above.
    t_ofs_plat_clock_reset_pair pClk;
    t_ofs_plat_clock_reset_pair pClkDiv2;
    t_ofs_plat_clock_reset_pair pClkDiv4;
    t_ofs_plat_clock_reset_pair uClk_usr;
    t_ofs_plat_clock_reset_pair uClk_usrDiv2;
}
t_ofs_plat_std_clocks;

`endif // __OFS_PLAT_CLOCKS_VH__
