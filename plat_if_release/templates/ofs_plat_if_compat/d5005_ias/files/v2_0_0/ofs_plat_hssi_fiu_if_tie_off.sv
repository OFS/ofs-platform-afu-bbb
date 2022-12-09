// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


//
// Tie off a single hssi_if port.
//

`include "ofs_plat_if.vh"

module ofs_plat_hssi_fiu_if_tie_off
   (
    pr_hssi_if.to_fiu port
    );

    always_comb
    begin
        port.a2f_tx_parallel_data = '0;
        port.a2f_rx_bitslip = '0;
        port.a2f_rx_fifo_rd_en = '0;
        port.a2f_rx_seriallpbken = '0;
        port.a2f_channel_reset = '0;
    end

endmodule // ofs_plat_hssi_fiu_if_tie_off
