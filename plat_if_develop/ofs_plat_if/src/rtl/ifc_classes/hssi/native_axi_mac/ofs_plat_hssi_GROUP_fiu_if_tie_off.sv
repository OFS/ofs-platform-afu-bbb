// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


//
// Tie off a single hssi_if channel.
//

`include "ofs_plat_if.vh"

module ofs_plat_hssi_@group@_fiu_if_tie_off
   (
    ofs_plat_hssi_@group@_channel_if channel
    );

    always_comb
    begin
        channel.data_rx.tready = 1'b0;
        channel.data_tx.tx = '0;
        channel.sb_tx.sb = '0;
    end

endmodule // ofs_plat_hssi_@group@_fiu_if_tie_off
