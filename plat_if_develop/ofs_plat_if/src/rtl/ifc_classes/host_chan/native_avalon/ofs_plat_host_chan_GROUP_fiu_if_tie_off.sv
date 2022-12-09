// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


//
// Tie off a single host channel interface port.
//
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_@group@_fiu_if_tie_off
   (
    ofs_plat_avalon_mem_if.to_sink port
    );

    always_comb
    begin
        port.read = 1'b0;
        port.write = 1'b0;
    end

endmodule // ofs_plat_host_chan_@group@_fiu_if_tie_off
