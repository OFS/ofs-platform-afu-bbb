//
// Copyright (c) 2020, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

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
