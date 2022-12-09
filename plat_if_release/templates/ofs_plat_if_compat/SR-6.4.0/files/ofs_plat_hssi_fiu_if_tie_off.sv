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
        port.a2f_init_start = '0;
        port.a2f_tx_analogreset = '0;
        port.a2f_tx_digitalreset = '0;
        port.a2f_rx_analogreset = '0;
        port.a2f_rx_digitalreset = '0;
        port.a2f_rx_seriallpbken = '0;
        port.a2f_rx_set_locktoref = '0;
        port.a2f_rx_set_locktodata = '0;
        port.a2f_tx_parallel_data = '0;
        port.a2f_tx_control = '0;
        port.a2f_rx_enh_fifo_rd_en = '0;
        port.a2f_tx_enh_data_valid = '0;
        port.a2f_prmgmt_fatal_err = '0;
        port.a2f_prmgmt_dout = '0;
    end

endmodule // ofs_plat_hssi_fiu_if_tie_off
