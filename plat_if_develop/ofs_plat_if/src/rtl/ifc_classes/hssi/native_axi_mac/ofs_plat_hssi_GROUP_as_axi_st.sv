// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Export an Ethernet interface channel group as AXI streams.
//

`include "ofs_plat_if.vh"

module ofs_plat_hssi_@group@_as_axi_st
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

    // Individual AXI streams for use in the AFU
    ofs_fim_eth_rx_axis_if.master eth_rx_st,
    ofs_fim_eth_tx_axis_if.slave  eth_tx_st,

    ofs_fim_eth_sideband_rx_axis_if.master eth_sb_rx,
    ofs_fim_eth_sideband_tx_axis_if.slave  eth_sb_tx,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    ofs_fim_eth_axis_connect_rx connect_rx
      (
       .to_afu(eth_rx_st),
       .to_fim(to_fiu.data_rx)
       );

    ofs_fim_eth_axis_connect_tx connect_tx
      (
       .to_afu(eth_tx_st),
       .to_fim(to_fiu.data_tx)
       );

    ofs_fim_eth_axis_connect_sb_rx connect_sb_rx
      (
       .to_afu(eth_sb_rx),
       .to_fim(to_fiu.sb_rx)
       );

    ofs_fim_eth_axis_connect_sb_tx connect_sb_tx
      (
       .to_afu(eth_sb_tx),
       .to_fim(to_fiu.sb_tx)
       );

endmodule // ofs_plat_hssi_@group@_as_axi_st
