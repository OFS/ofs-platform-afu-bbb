//
// Copyright (c) 2019, Intel Corporation
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
// Export an Avalon split-bus read/write interface to an AFU, given an
// FIU interface that is a normal Avalon memory mapped port. The module here
// offers clock crossing and extra register stages.
//
// MMIO is not implemented through native Avalon interfaces.
//

`include "ofs_plat_if.vh"

//
// Host memory as Avalon (no MMIO).
//
module ofs_plat_host_chan_@group@_as_avalon_mem_rdwr
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
    ofs_plat_avalon_mem_if.to_sink to_fiu,

    ofs_plat_avalon_mem_rdwr_if.to_source_clk host_mem_to_afu,

    // AFU clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,
    input  logic afu_reset_n
    );

    // Apply clock crossing and burst mapping to the Avalon sink.
    ofs_plat_avalon_mem_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(host_mem_to_afu)
        )
      afu_avmm_if();

    ofs_plat_host_chan_@group@_as_avalon_mem
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
        )
      avmm
       (
        .to_fiu,
        .host_mem_to_afu(afu_avmm_if),
        .afu_clk,
        .afu_reset_n
        );

    // Export the simple Avalon interface as a split-bus interface.
    // passing the clock.
    ofs_plat_avalon_mem_rdwr_if
      #(
        `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS(host_mem_to_afu)
        )
      afu_mem_rdwr_if();

    ofs_plat_avalon_mem_rdwr_if_to_mem_if gen_rdwr
       (
        .mem_sink(afu_avmm_if),
        .mem_source(afu_mem_rdwr_if)
        );

    assign afu_mem_rdwr_if.clk = afu_avmm_if.clk;
    assign afu_mem_rdwr_if.reset_n = afu_avmm_if.reset_n;
    assign afu_mem_rdwr_if.instance_number = afu_avmm_if.instance_number;

    // Make the final connection to the host_mem_to_afu instance, including
    // passing the clock.
    ofs_plat_avalon_mem_rdwr_if_connect_sink_clk conn_to_afu
       (
        .mem_sink(afu_mem_rdwr_if),
        .mem_source(host_mem_to_afu)
        );

endmodule // ofs_plat_host_chan_@group@_as_avalon_mem_rdwr
