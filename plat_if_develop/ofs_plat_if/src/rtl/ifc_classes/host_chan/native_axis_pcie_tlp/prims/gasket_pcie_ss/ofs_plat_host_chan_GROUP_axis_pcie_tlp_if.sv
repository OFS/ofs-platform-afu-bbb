// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Platform-specific interface to FIM. The interface is specified here, in
// the gaskets tree, because the data structures and protocols may be vary
// by platform.
//

interface ofs_plat_host_chan_@group@_axis_pcie_tlp_if
  #(
    // Log events for this instance?
    parameter ofs_plat_log_pkg::t_log_class LOG_CLASS = ofs_plat_log_pkg::NONE
    );

    wire clk;
    logic reset_n;

    // Debugging state.  This will typically be driven to a constant by the
    // code that instantiates the interface object.
    int unsigned instance_number;

    int link_num;

    // PCIe PF/VF details. Meaningful only when OFS_PLAT_HOST_CHAN_MULTIPLEXED is
    // not set by the AFU.
    ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_pfvf_id pfvf;

    // Multiplexed version of pfvf above. Enumerates all PFs/VFs that share the
    // stream when OFS_PLAT_HOST_CHAN_MULTIPLEXED is set by the AFU.
    ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_pfvf_id [ofs_plat_host_chan_@group@_fim_gasket_pkg::NUM_CHAN_PER_MULTIPLEXED_PORT-1:0] multiplexed_pfvfs;
    ofs_plat_host_chan_@group@_fim_gasket_pkg::t_multiplexed_port_id num_multiplexed_pfvfs;
    ofs_plat_host_chan_@group@_fim_gasket_pkg::e_pcie_vchan_mapping_alg vchan_mapping_alg;

    // AFU -> FIM TLP TX stream
    pcie_ss_axis_if#(.DATA_W(ofs_plat_host_chan_@group@_fim_gasket_pkg::TDATA_WIDTH))
        afu_tx_a_st(clk, reset_n);

    // AFU -> FIM TLP TX B stream. The PIM uses this port for read requests.
    pcie_ss_axis_if#(.DATA_W(ofs_plat_host_chan_@group@_fim_gasket_pkg::TDATA_WIDTH))
        afu_tx_b_st(clk, reset_n);

    // FIM -> AFU TLP RX A stream. This is the primary response stream from the host.
    pcie_ss_axis_if#(.DATA_W(ofs_plat_host_chan_@group@_fim_gasket_pkg::TDATA_WIDTH))
        afu_rx_a_st(clk, reset_n);

    // FIM -> AFU TLP RX B stream. This stream is only FIM-generated write completions
    // to signal that the TX A/B arbitration is complete and a write is committed.
    pcie_ss_axis_if#(.DATA_W(ofs_plat_host_chan_@group@_fim_gasket_pkg::TDATA_WIDTH))
        afu_rx_b_st(clk, reset_n);

endinterface // ofs_plat_host_chan_@group@_axis_pcie_tlp_if
