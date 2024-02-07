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
    ofs_fim_hssi_ss_rx_axis_if.mac rx_st,
    ofs_fim_hssi_ss_tx_axis_if.mac tx_st,

    ofs_fim_hssi_fc_if.mac         fc,

    // These are present in all PIM interfaces, though not used here.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    ofs_fim_hssi_axis_connect_rx connect_rx
      (
       .to_client(rx_st),
       .to_mac(to_fiu.data_rx)
       );

    ofs_fim_hssi_axis_connect_tx connect_tx
      (
       .to_client(tx_st),
       .to_mac(to_fiu.data_tx)
       );

    ofs_fim_hssi_connect_fc connect_fc
      (
       .to_client(fc),
       .to_mac(to_fiu.fc)
       );

endmodule // ofs_plat_hssi_@group@_as_axi_st
