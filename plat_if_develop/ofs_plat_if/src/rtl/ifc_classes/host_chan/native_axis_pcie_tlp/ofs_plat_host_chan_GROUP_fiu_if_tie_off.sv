// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


//
// Tie off a single host channel interface port.
//
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_@group@_fiu_if_tie_off
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if port
    );

    // FIM-specific tie off
    ofs_plat_host_chan_@group@_fim_gasket_tie_off tie_off(.port);

endmodule
