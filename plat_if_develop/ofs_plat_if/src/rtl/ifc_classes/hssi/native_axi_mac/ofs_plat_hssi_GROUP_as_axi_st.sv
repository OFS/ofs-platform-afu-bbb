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
