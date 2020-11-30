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
// Export a platform local_mem interface to an AFU as an AXI memory.
//
// The "as AXI" abstraction here allows an AFU to request the memory
// using a particular interface. The platform may offer multiple interfaces
// to the same underlying PR wires, instantiating protocol conversion
// shims as needed.
//

//
// This version of ofs_plat_local_mem_as_axi_mem works on platforms
// where the native interface is already AXI.
//

`include "ofs_plat_if.vh"

module ofs_plat_local_mem_@group@_as_axi_mem
  #(
    // When non-zero, add a clock crossing to move the AFU interface
    // to the passed in afu_clk.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages, typically for timing.
    parameter ADD_TIMING_REG_STAGES = 0,

    // Should read or write responses be returned in the order they were
    // requested? For now, we assume that AXI local memory interfaces
    // already return responses in order. They are defined so the interface
    // remains consistent with future devices that may return responses out
    // of order.
    parameter SORT_READ_RESPONSES = 1,
    parameter SORT_WRITE_RESPONSES = 1
    )
   (
    // AFU clock for memory when a clock crossing is requested
    input  logic afu_clk,
    input  logic afu_reset_n,

    // The ports are named "to_fiu" and "to_afu" despite the AXI
    // to_sink/to_source naming because the PIM port naming is a
    // bus-independent abstraction. At top-level, PIM ports are
    // always to_fiu and to_afu.
    ofs_plat_axi_mem_if.to_sink to_fiu,
    ofs_plat_axi_mem_if.to_source_clk to_afu
    );


    //
    // How many register stages should be inserted for timing?
    //
    function automatic int numTimingRegStages();
        // Were timing registers requested?
        int n_stages = ADD_TIMING_REG_STAGES;

        // Use at least two stages
        if (n_stages < 2)
            n_stages = 2;

        // Use at least the recommended number of stages
        if (`OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_SUGGESTED_TIMING_REG_STAGES > n_stages)
        begin
            n_stages = `OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_SUGGESTED_TIMING_REG_STAGES;
        end

        return n_stages;
    endfunction

    localparam NUM_TIMING_REG_STAGES = numTimingRegStages();

    //
    // Connect to the to_afu instance, including passing the clock.
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(to_afu)
        )
      axi_afu_if();

    assign axi_afu_if.clk = (ADD_CLOCK_CROSSING == 0) ? to_fiu.clk : afu_clk;
    assign axi_afu_if.instance_number = to_fiu.instance_number;

    logic reset_n = 1'b0;
    always @(posedge axi_afu_if.clk)
    begin
        reset_n <= (ADD_CLOCK_CROSSING == 0) ? to_fiu.reset_n : afu_reset_n;
    end

    assign axi_afu_if.reset_n = reset_n;

    ofs_plat_axi_mem_if_connect_sink_clk conn_to_afu
       (
        .mem_source(to_afu),
        .mem_sink(axi_afu_if)
        );


    //
    // Map AFU-sized bursts to FIU-sized bursts. (The AFU may generate larger
    // bursts than the FIU will accept.)
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_MEM_PARAMS(to_afu),
        .BURST_CNT_WIDTH(to_fiu.BURST_CNT_WIDTH_),
        .RID_WIDTH(to_afu.RID_WIDTH_),
        .WID_WIDTH(to_afu.WID_WIDTH_),
        .USER_WIDTH(to_afu.USER_WIDTH_)
        )
      axi_fiu_burst_if();

    assign axi_fiu_burst_if.clk = axi_afu_if.clk;
    assign axi_fiu_burst_if.reset_n = axi_afu_if.reset_n;
    assign axi_fiu_burst_if.instance_number = to_fiu.instance_number;

    ofs_plat_axi_mem_if_map_bursts
      #(
        .UFLAG_NO_REPLY(ofs_plat_local_mem_axi_mem_pkg::LM_AXI_UFLAG_NO_REPLY)
        )
      map_bursts
       (
        .mem_source(axi_afu_if),
        .mem_sink(axi_fiu_burst_if)
        );


    //
    // Preserve AFU user and extra ID bits and return them with responses.
    // The PIM adds extra state to AXI user fields that devices may not
    // implement.
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_MEM_PARAMS(to_afu),
        .BURST_CNT_WIDTH(to_fiu.BURST_CNT_WIDTH_),
        .RID_WIDTH(to_fiu.RID_WIDTH_),
        .WID_WIDTH(to_fiu.WID_WIDTH_),
        .USER_WIDTH(to_fiu.USER_WIDTH_)
        )
      axi_fiu_user_if();

    assign axi_fiu_user_if.clk = axi_afu_if.clk;
    assign axi_fiu_user_if.reset_n = axi_afu_if.reset_n;
    assign axi_fiu_user_if.instance_number = to_fiu.instance_number;

    ofs_plat_axi_mem_if_user_ext
      #(
        .FIM_USER_WIDTH(`OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_USER_WIDTH)
        )
      map_user
       (
        .mem_source(axi_fiu_burst_if),
        .mem_sink(axi_fiu_user_if)
        );


    //
    // Clock crossing between AFU and FIU?
    //
    generate
        if (ADD_CLOCK_CROSSING == 0)
        begin : nc
            //
            // No clock crossing, maybe register stages.
            //
            ofs_plat_axi_mem_if_reg
              #(
                .N_REG_STAGES(NUM_TIMING_REG_STAGES)
                )
              mem_pipe
               (
                .mem_source(axi_fiu_user_if),
                .mem_sink(to_fiu)
                );
        end
        else
        begin : cc
            //
            // Clock crossing to sink clock.
            //
            ofs_plat_axi_mem_if
              #(
                `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(to_fiu)
                )
              axi_fiu_clk_if();

            ofs_plat_axi_mem_if_async_shim
              #(
                .ADD_TIMING_REG_STAGES(NUM_TIMING_REG_STAGES),
                .NUM_READ_CREDITS(`OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_MAX_BW_ACTIVE_LINES_RD),
                .NUM_WRITE_CREDITS(`OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_MAX_BW_ACTIVE_LINES_WR)
                )
              async_shim
               (
                .mem_source(axi_fiu_user_if),
                .mem_sink(axi_fiu_clk_if)
                );


            //
            // Connect to the FIU
            //
            ofs_plat_axi_mem_if_reg_sink_clk
              #(
                .N_REG_STAGES(1)
                )
              mem_pipe
               (
                .mem_source(axi_fiu_clk_if),
                .mem_sink(to_fiu)
                );
        end
    endgenerate

endmodule // ofs_plat_local_mem_@group@_as_axi_mem
