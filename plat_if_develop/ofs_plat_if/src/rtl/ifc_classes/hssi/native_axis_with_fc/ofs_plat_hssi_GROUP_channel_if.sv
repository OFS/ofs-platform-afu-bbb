// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

`ifdef SIM_MODE
  // This file is on the search path only in simulation, which is a little unfortunate
  // but not a major problem. The file is included only to test for the simulation
  // debug logging functions under OFS_FIM_ETH_PROVIDES_HSSI_TO_STRING below.
  `include "ofs_fim_eth_plat_defines.svh"
`endif


//
// All streams associated with a single channel's data and sideband metadata.
//=
//= _@group@ is replaced with the group number by the gen_ofs_plat_if script
//= as it generates a platform-specific build/platform/ofs_plat_if tree.
//
interface ofs_plat_hssi_@group@_channel_if
  #(
    // Log events for this instance?
    parameter ofs_plat_log_pkg::t_log_class LOG_CLASS = ofs_plat_log_pkg::NONE
    );

    import ofs_fim_eth_if_pkg::*;

    // All interfaces share a common clock
    wire clk;
    logic reset_n;

    // HSSI -> AFU
    ofs_fim_hssi_ss_rx_axis_if data_rx();
    // AFU -> HSSI
    ofs_fim_hssi_ss_tx_axis_if data_tx();

    // Flow control
    ofs_fim_hssi_fc_if fc();


    //
    // Debugging
    //

//
// The func_axis_hssi_ss_*_to_string functions were not available from OFS
// until mid-2023. HSSI logging depends on them.
//
`ifdef OFS_FIM_ETH_PROVIDES_HSSI_TO_STRING

    // This will typically be driven to a constant by the
    // code that instantiates the interface object.
    int unsigned instance_number;

    // synthesis translate_off

    initial
    begin
        static string ctx_name = $sformatf("%m");

        // Watch traffic
        if (LOG_CLASS != ofs_plat_log_pkg::NONE)
        begin
            static int log_fd = ofs_plat_log_pkg::get_fd(LOG_CLASS);

            forever @(posedge data_rx.clk)
            begin
                if (data_rx.rst_n && data_rx.rx.tvalid)
                begin
                    $fwrite(log_fd, "%s: %t %s %0d RX %s\n",
                            ctx_name, $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            ofs_fim_eth_if_pkg::func_axis_hssi_ss_rx_to_string(data_rx.rx));
                end

                if (data_tx.rst_n && data_tx.tx.tvalid && data_tx.tready)
                begin
                    $fwrite(log_fd, "%s: %t %s %0d TX %s\n",
                            ctx_name, $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            ofs_fim_eth_if_pkg::func_axis_hssi_ss_tx_to_string(data_tx.tx));
                end
            end
        end
    end

    // synthesis translate_on

`endif //  `ifdef OFS_FIM_ETH_PROVIDES_HSSI_TO_STRING

endinterface // ofs_plat_hssi_@group@_channel_if
