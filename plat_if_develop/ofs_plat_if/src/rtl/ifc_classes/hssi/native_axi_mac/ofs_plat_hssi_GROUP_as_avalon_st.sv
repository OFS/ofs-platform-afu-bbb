// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Export an Ethernet interface channel group as Avalon streams.
//

`include "ofs_plat_if.vh"

module ofs_plat_hssi_@group@_as_avalon_st
  #(
    // When non-zero, add a clock crossing to move the AFU
    // interface to the clock/reset_n pair passed in afu_clk/afu_reset_n.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0
    )
   (
    // Wrapper interface holding all four streams to the MAC
    ofs_plat_hssi_@group@_channel_if to_fiu,

    // Individual Avalon streams for use in the AFU
    ofs_fim_eth_rx_avst_if.master eth_rx_st,
    ofs_fim_eth_tx_avst_if.slave  eth_tx_st,

    ofs_fim_eth_sideband_rx_avst_if.master eth_sb_rx,
    ofs_fim_eth_sideband_tx_avst_if.slave  eth_sb_tx,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    // Use a FIM-provided bridge to map the AXI-S encoding to AVST
    ofs_fim_eth_afu_avst_to_fim_axis_bridge axis_to_avst_bridge_inst
       (
        .avst_tx_st(eth_tx_st),
        .avst_rx_st(eth_rx_st),
        .axi_tx_st(to_fiu.data_tx),
        .axi_rx_st(to_fiu.data_rx)
        );

    ofs_fim_eth_sb_afu_avst_to_fim_axis_bridge sb_axis_to_avst_bridge_inst
       (
        .avst_tx_st(eth_sb_tx),
        .avst_rx_st(eth_sb_rx),
        .axi_tx_st(to_fiu.sb_tx),
        .axi_rx_st(to_fiu.sb_rx)
        );

endmodule // ofs_plat_hssi_@group@_as_avalon_st
