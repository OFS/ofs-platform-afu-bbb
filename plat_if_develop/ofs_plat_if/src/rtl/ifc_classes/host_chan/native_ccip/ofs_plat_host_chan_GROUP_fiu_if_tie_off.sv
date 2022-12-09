// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


//
// Tie off a single host channel interface port.
//
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_@group@_fiu_if_tie_off
   (
    ofs_plat_host_ccip_if.to_fiu port
    );

    always_comb
    begin
        port.sTx.c0.valid = 1'b0;
        port.sTx.c1.valid = 1'b0;
        port.sTx.c2.mmioRdValid = 1'b0;
    end

endmodule // ofs_plat_host_chan_@group@_fiu_if_tie_off
