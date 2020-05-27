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
// where the native interface is Avalon.
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
    // requested? Native Avalon will already return responses in order,
    // so these don't matter in this case. They are defined so the interface
    // remains consistent with devices that return responses out of order.
    parameter SORT_READ_RESPONSES = 1,
    parameter SORT_WRITE_RESPONSES = 1
    )
   (
    // AFU clock for memory when a clock crossing is requested
    input  logic afu_clk,
    input  logic afu_reset_n,

    // The ports are named "to_fiu" and "to_afu" despite the Avalon
    // to_slave/to_master naming because the PIM port naming is a
    // bus-independent abstraction. At top-level, PIM ports are
    // always to_fiu and to_afu.
    ofs_plat_avalon_mem_if.to_slave to_fiu,
    ofs_plat_axi_mem_if.to_master_clk to_afu
    );

    // ====================================================================
    //
    // While clocking and register stage insertion are logically
    // independent, considering them together leads to an important
    // optimization. The clock crossing FIFO has a large buffer that
    // can be used to turn the standard Avalon MM waitrequest signal into
    // an almost full protocol. The buffer stages become a simple
    // pipeline.
    //
    // When there is no clock crossing FIFO, all register stages must
    // honor the waitrequest protocol.
    //
    // ====================================================================

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

    ofs_plat_axi_mem_if_connect_slave_clk conn_to_afu
       (
        .mem_master(to_afu),
        .mem_slave(axi_afu_if)
        );


    //
    // Map AFU-sized bursts to FIU-sized bursts. (The AFU may generate larger
    // bursts than the FIU will accept.)
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_MEM_PARAMS(to_afu),
        // Avalon burst count of the slave, mapped to AXI size
        .BURST_CNT_WIDTH(to_fiu.BURST_CNT_WIDTH_ - 1),
        .RID_WIDTH(to_afu.RID_WIDTH_),
        .WID_WIDTH(to_afu.WID_WIDTH_),
        // Extra bit to tag bursts generated inside the burst mapper
        .USER_WIDTH(to_afu.USER_WIDTH_ + 1)
        )
      axi_fiu_burst_if();

    assign axi_fiu_burst_if.clk = axi_afu_if.clk;
    assign axi_fiu_burst_if.reset_n = axi_afu_if.reset_n;
    assign axi_fiu_burst_if.instance_number = to_fiu.instance_number;

    ofs_plat_axi_mem_if_map_bursts map_bursts
       (
        .mem_master(axi_afu_if),
        .mem_slave(axi_fiu_burst_if)
        );


    //
    // Protect the read and write response buffers from overflow by tracking
    // buffer credits. The memory driver in the FIM has no flow control.
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(axi_fiu_burst_if)
        )
      axi_fiu_credit_if();

    assign axi_fiu_credit_if.clk = axi_afu_if.clk;
    assign axi_fiu_credit_if.reset_n = axi_afu_if.reset_n;
    assign axi_fiu_credit_if.instance_number = to_fiu.instance_number;

    ofs_plat_axi_mem_if_rsp_credits
      #(
        .NUM_READ_CREDITS(`OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_MAX_BW_ACTIVE_LINES_RD),
        .NUM_WRITE_CREDITS(`OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_MAX_BW_ACTIVE_LINES_WR)
        )
      rsp_credits
       (
        .mem_master(axi_fiu_burst_if),
        .mem_slave(axi_fiu_credit_if)
        );


    //
    // Clock crossing to slave clock. We insert this unconditionally because
    // response buffers are needed anyway and the clock-crossing FIFOs are
    // efficient. The FIFOs are also used for adding Hyperflex pipeline stages
    // in each direction.
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(axi_fiu_burst_if)
        )
      axi_fiu_clk_if();

    assign axi_fiu_clk_if.clk = to_fiu.clk;
    assign axi_fiu_clk_if.reset_n = to_fiu.reset_n;
    assign axi_fiu_clk_if.instance_number = to_fiu.instance_number;

    ofs_plat_axi_mem_if_async_shim
      #(
        .ADD_TIMING_REG_STAGES(NUM_TIMING_REG_STAGES),
        .SLAVE_RESPONSES_ALWAYS_READY(1),
        .NUM_READ_CREDITS(`OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_MAX_BW_ACTIVE_LINES_RD),
        .NUM_WRITE_CREDITS(`OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_MAX_BW_ACTIVE_LINES_WR)
        )
      async_shim
       (
        .mem_master(axi_fiu_credit_if),
        .mem_slave(axi_fiu_clk_if)
        );


    //
    // Map AXI master to Avalon split-bus read/write slave.
    //

    // Larger of RID/WID
    localparam ID_WIDTH = (to_afu.RID_WIDTH > to_afu.WID_WIDTH) ? to_afu.RID_WIDTH : to_afu.WID_WIDTH;
    // Avalon user width must hold AXI "id" and "user" fields
    localparam AVMM_USER_WIDTH = to_afu.USER_WIDTH + 1 + ID_WIDTH;

    ofs_plat_avalon_mem_rdwr_if
      #(
        .ADDR_WIDTH(to_afu.ADDR_LINE_IDX_WIDTH),
        .DATA_WIDTH(to_afu.DATA_WIDTH_),
        .MASKED_SYMBOL_WIDTH(to_afu.MASKED_SYMBOL_WIDTH_),
        .BURST_CNT_WIDTH(to_fiu.BURST_CNT_WIDTH_),
        .USER_WIDTH(AVMM_USER_WIDTH)
        )
      avmm_rdwr_if();

    assign avmm_rdwr_if.clk = to_fiu.clk;
    assign avmm_rdwr_if.reset_n = to_fiu.reset_n;
    assign avmm_rdwr_if.instance_number = to_fiu.instance_number;

    // synthesis translate_off
    initial
    begin
        if (avmm_rdwr_if.DATA_WIDTH_ > to_fiu.DATA_WIDTH_)
        begin
            $fatal(2, "** ERROR ** %m: AFU memory DATA_WIDTH (%0d) is wider than FIU (%0d)!",
                   avmm_rdwr_if.DATA_WIDTH_, to_fiu.DATA_WIDTH_);
        end
    end
    // synthesis translate_on

    ofs_plat_axi_mem_if_to_avalon_rdwr_if
      #(
        .GEN_RD_RESPONSE_METADATA(1),
        .RD_RESPONSE_FIFO_DEPTH(`OFS_PLAT_PARAM_LOCAL_MEM_@GROUP@_MAX_BW_ACTIVE_LINES_RD)
        )
      axi_to_avmm_rdwr
       (
        .axi_master(axi_fiu_clk_if),
        .avmm_slave(avmm_rdwr_if)
        );


    //
    // Map Avalon split-bus read/write to straight Avalon slave.
    //
    ofs_plat_avalon_mem_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(to_fiu),
        .USER_WIDTH(1)
        )
        avmm_if();

    ofs_plat_avalon_mem_rdwr_if_to_mem_if
      #(
        .LOCAL_WR_RESPONSE(1)
        )
      avmm_rdwr_to_avmm
       (
        .mem_master(avmm_rdwr_if),
        .mem_slave(avmm_if)
        );


    //
    // Connect to the FIU
    //
    ofs_plat_avalon_mem_if_reg_slave_clk
      #(
        .N_REG_STAGES(1)
        )
      mem_pipe
       (
        .mem_master(avmm_if),
        .mem_slave(to_fiu)
        );

endmodule // ofs_plat_local_mem_@group@_as_avalon_mem
