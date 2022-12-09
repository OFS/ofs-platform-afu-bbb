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
        channel.data_tx.tx = '0;
        channel.fc.tx_pause = '0;
        channel.fc.tx_pfc = '0;
    end

endmodule // ofs_plat_hssi_@group@_fiu_if_tie_off
