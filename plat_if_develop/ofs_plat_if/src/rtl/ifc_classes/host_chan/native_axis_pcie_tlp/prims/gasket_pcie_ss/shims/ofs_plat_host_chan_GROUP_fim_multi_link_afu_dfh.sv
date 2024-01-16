// Copyright 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// A PIM wrapper around the FIM-provided module that generates parent/child
// feature headers. It takes the same parameters as the FIM module.
//
// The incoming host channel port wrapper (to_fiu) adds the shim and exports
// a new host channel port wrapper (to_afu) that can then be passed to
// standard PIM host channel transformations.
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_@group@_fim_multi_link_afu_dfh
  #(
    // For a child AFU, leave NUM_CHILDREN set to zero. A parent AFU header is
    // constructed when NUM_CHILDREN is non-zero.
    parameter NUM_CHILDREN = 0,
    // When the AFU is a parent (NUM_CHILDREN > 0), set CHILD_GUIDs to an array
    // of child GUIDs on which the parent depends.
    parameter logic [127:0] CHILD_GUIDS[NUM_CHILDREN == 0 ? 1 : NUM_CHILDREN] = {'0},

    // Byte offset to the next feature. If non-zero, the next feature's MMIO
    // traffic must be handled by the AFU.
    parameter logic [23:0] NEXT_DFH = '0,

    // Byte offset to a CSR region. If non-zero, CSR traffic must be handled
    // by the AFU. The CSR region must be outside of the AFU feature managed
    // by this module.
    parameter logic [63:0] CSR_ADDR = '0,
    parameter logic [31:0] CSR_SIZE = '0,

    // When set to one this module will respond to all MMIO reads. When zero,
    // reads outside of the main AFU feature will be forwarded to o_rx_if.
    // All MMIO writes are forwarded to o_rx_if unconditionally.
    // By default, all MMIO reads are handled here if both NEXT_DFH and
    // CSR_ADDR are zero.
    parameter logic HANDLE_ALL_MMIO_READS = !NEXT_DFH && !CSR_ADDR,

    // MMIO byte address size
    parameter MMIO_ADDR_WIDTH = `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_MMIO_ADDR_WIDTH,

    parameter logic [63:0] GUID_H,
    parameter logic [63:0] GUID_L
    )
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu,
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_afu
    );

    wire clk = to_fiu.clk;
    wire rst_n = to_fiu.reset_n;

    assign to_afu.clk = to_fiu.clk;
    assign to_afu.reset_n = to_fiu.reset_n;
    assign to_afu.instance_number = to_fiu.instance_number;

    assign to_afu.pf_num = to_fiu.pf_num;
    assign to_afu.vf_num = to_fiu.vf_num;
    assign to_afu.vf_active = to_fiu.vf_active;

    //
    // FIM-provided shim for generating parent/child feature headers.
    //
    ofs_fim_pcie_multi_link_afu_dfh
      #(
        .NUM_CHILDREN(NUM_CHILDREN),
        .CHILD_GUIDS(CHILD_GUIDS),
        .NEXT_DFH(NEXT_DFH),
        .CSR_ADDR(CSR_ADDR),
        .CSR_SIZE(CSR_SIZE),
        .HANDLE_ALL_MMIO_READS(HANDLE_ALL_MMIO_READS),
        .MMIO_ADDR_WIDTH(MMIO_ADDR_WIDTH),
        .GUID_H(GUID_H),
        .GUID_L(GUID_L)
        )
      dfh
       (
        .i_rx_if(to_fiu.afu_rx_a_st),
        .o_rx_if(to_afu.afu_rx_a_st),
        .o_tx_if(to_fiu.afu_tx_a_st),
        .i_tx_if(to_afu.afu_tx_a_st)
        );


    //
    // Connect B ports. They don't go through the shim above.
    //
    ofs_fim_axis_pipeline
      #(
        .PL_DEPTH(0),
        .TDATA_WIDTH(ofs_plat_host_chan_@group@_fim_gasket_pkg::TDATA_WIDTH)
        )
      rx_b
       (
        .clk,
        .rst_n,
        .axis_s(to_fiu.afu_rx_b_st),
        .axis_m(to_afu.afu_rx_b_st)
        );

    ofs_fim_axis_pipeline
      #(
        .PL_DEPTH(0),
        .TDATA_WIDTH(ofs_plat_host_chan_@group@_fim_gasket_pkg::TDATA_WIDTH)
        )
      tx_b
       (
        .clk,
        .rst_n,
        .axis_s(to_afu.afu_tx_b_st),
        .axis_m(to_fiu.afu_tx_b_st)
        );

endmodule // ofs_plat_host_chan_@group@_fim_multi_link_afu_dfh
