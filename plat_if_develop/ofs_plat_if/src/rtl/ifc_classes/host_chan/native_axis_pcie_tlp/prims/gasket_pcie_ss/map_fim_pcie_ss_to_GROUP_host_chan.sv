// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Map the PCIe SS AXI-S interface exposed by the FIM to the PIM's representation.
// The payload is the same in both. The PIM adds extra decoration to encode
// SOP flags within the user field and uses a consistent AXI-S interface
// declaration across all PIM-managed devices.
//
// There are two streams per port: A and B. TX B is used for read requests. TX A
// is used for all others. The two ports do not have a defined relative order.
// RX A has standard host to FPGA traffic. RX B has Cpl messages (without data),
// synthesized by the FIM in response to TX A write requests at the commit point
// where TX A and B are ordered.
//

`include "ofs_plat_if.vh"

//
// Primary wrapper for mapping a collection of four FIM TLP streams into a
// logical PIM port. There are two streams in each direction, with the "B"
// ports intended for transmitting reads that may flow around writes.
//
module map_fim_pcie_ss_to_pim_@group@_host_chan
  #(
    // Instance number is just used for debugging as a tag
    parameter INSTANCE_NUMBER = 0,

    // PCIe PF/VF details
`ifdef OFS_PLAT_HOST_CHAN_MULTIPLEXED
    parameter NUM_PF_VF_INFO_ENTRIES = ofs_plat_host_chan_@group@_pkg::NUM_CHAN_PER_MULTIPLEXED_PORT,
    parameter pcie_ss_hdr_pkg::ReqHdr_pf_vf_info_t [NUM_PF_VF_INFO_ENTRIES-1:0] PORT_PF_VF_INFO
`else
    parameter NUM_PF_VF_INFO_ENTRIES = 1,
    parameter pcie_ss_hdr_pkg::ReqHdr_pf_num_t PF_NUM,
    parameter pcie_ss_hdr_pkg::ReqHdr_vf_num_t VF_NUM,
    parameter VF_ACTIVE,
    parameter LINK_NUM = 0
`endif
    )
   (
    // All streams are expected to share the same clock and reset
    input  logic clk,
    // Force 'x to 0
    input  bit   reset_n,

    // FIM interfaces
    pcie_ss_axis_if.source pcie_ss_tx_a_st,
    pcie_ss_axis_if.source pcie_ss_tx_b_st,
    pcie_ss_axis_if.sink pcie_ss_rx_a_st,
    pcie_ss_axis_if.sink pcie_ss_rx_b_st,

    // PIM wrapper for the FIM interfaces
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if port
    );

    assign port.clk = clk;
    assign port.reset_n = reset_n;

    assign port.instance_number = INSTANCE_NUMBER;
`ifdef OFS_PLAT_HOST_CHAN_MULTIPLEXED
    assign port.link_num = PORT_PF_VF_INFO[0].link_num;
    assign port.num_multiplexed_pfvfs = NUM_PF_VF_INFO_ENTRIES;
    for (genvar p = 0; p < NUM_PF_VF_INFO_ENTRIES; p = p + 1) begin
        // PF/VF details of all SR-IOV streams multiplexed in the port
        assign port.multiplexed_pfvfs[p].vf_num = PORT_PF_VF_INFO[p].vf_num;
        assign port.multiplexed_pfvfs[p].vf_active = PORT_PF_VF_INFO[p].vf_active;
        assign port.multiplexed_pfvfs[p].pf_num = PORT_PF_VF_INFO[p].pf_num;
    end
`else
    // Single PF/VF in the port, already demultiplexed
    assign port.link_num = LINK_NUM;
    assign port.num_multiplexed_pfvfs = 1;
    assign port.multiplexed_pfvfs[0].vf_num = VF_NUM;
    assign port.multiplexed_pfvfs[0].vf_active = VF_ACTIVE;
    assign port.multiplexed_pfvfs[0].pf_num = PF_NUM;
`endif

    // Backward compatibility -- meaningful only in demultiplexed mode
    assign port.pfvf = port.multiplexed_pfvfs[0];

    assign port.vchan_mapping_alg =
        ofs_plat_host_chan_@group@_fim_gasket_pkg::pick_vchan_mapping_alg(
            port.num_multiplexed_pfvfs, port.multiplexed_pfvfs);

    // Use the legacy module to map the streaming channels
    map_fim_pcie_ss_to_@group@_host_chan map
       (
        .pcie_ss_tx_a_st,
        .pcie_ss_tx_b_st,
        .pcie_ss_rx_a_st,
        .pcie_ss_rx_b_st,

        .pim_tx_a_st(port.afu_tx_a_st),
        .pim_tx_b_st(port.afu_tx_b_st),
        .pim_rx_a_st(port.afu_rx_a_st),
        .pim_rx_b_st(port.afu_rx_b_st)
        );

endmodule // map_fim_pcie_ss_to_pim_@group@_host_chan


//
// Mapping of individual FIM to PIM ports. Older code outside the PIM may
// also use this interface, so it is preserved here instead of being merged
// into the module above.
//
// Only the streaming ports are managed by this legacy interface.
//
module map_fim_pcie_ss_to_@group@_host_chan
   (
    // FIM interfaces
    pcie_ss_axis_if.source pcie_ss_tx_a_st,
    pcie_ss_axis_if.source pcie_ss_tx_b_st,
    pcie_ss_axis_if.sink pcie_ss_rx_a_st,
    pcie_ss_axis_if.sink pcie_ss_rx_b_st,

    // PIM interfaces (same as FIM interfaces, but they are wrapped in
    // the parent by the PIM host_chan interface).
    pcie_ss_axis_if.sink pim_tx_a_st,
    pcie_ss_axis_if.sink pim_tx_b_st,
    pcie_ss_axis_if.source pim_rx_a_st,
    pcie_ss_axis_if.source pim_rx_b_st
    );

`define OFS_PIM_CONNECT_PCIE_SS_IF(source_if, sink_if) \
    assign source_if.tready = sink_if.tready; \
    assign sink_if.tvalid = source_if.tvalid; \
    assign sink_if.tlast = source_if.tlast; \
    assign sink_if.tuser_vendor = source_if.tuser_vendor; \
    assign sink_if.tdata = source_if.tdata; \
    assign sink_if.tkeep = source_if.tkeep;

    `OFS_PIM_CONNECT_PCIE_SS_IF(pim_tx_a_st, pcie_ss_tx_a_st)
    `OFS_PIM_CONNECT_PCIE_SS_IF(pim_tx_b_st, pcie_ss_tx_b_st)
    `OFS_PIM_CONNECT_PCIE_SS_IF(pcie_ss_rx_a_st, pim_rx_a_st)
    `OFS_PIM_CONNECT_PCIE_SS_IF(pcie_ss_rx_b_st, pim_rx_b_st)

`undef OFS_PIM_CONNECT_PCIE_SS_IF

endmodule // map_fim_pcie_ss_to_@group@_host_chan
