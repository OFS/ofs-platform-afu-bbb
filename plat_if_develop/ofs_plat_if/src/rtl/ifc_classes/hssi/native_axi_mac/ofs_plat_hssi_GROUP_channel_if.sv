// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

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

    ofs_fim_eth_rx_axis_if data_rx();
    ofs_fim_eth_tx_axis_if data_tx();

    ofs_fim_eth_sideband_rx_axis_if sb_rx();
    ofs_fim_eth_sideband_tx_axis_if sb_tx();


    //
    // Debugging
    //

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
                if (data_rx.rst_n && data_rx.rx.tvalid && data_rx.tready)
                begin
                    $fwrite(log_fd, "%s: %t %s %0d RX %s\n",
                            ctx_name, $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            ofs_fim_eth_if_pkg::func_axis_eth_rx_to_string(data_rx.rx));
                end

                if (data_tx.rst_n && data_tx.tx.tvalid && data_tx.tready)
                begin
                    $fwrite(log_fd, "%s: %t %s %0d TX %s\n",
                            ctx_name, $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            ofs_fim_eth_if_pkg::func_axis_eth_tx_to_string(data_tx.tx));
                end
            end
        end
    end

    // synthesis translate_on

endinterface // ofs_plat_hssi_@group@_channel_if
