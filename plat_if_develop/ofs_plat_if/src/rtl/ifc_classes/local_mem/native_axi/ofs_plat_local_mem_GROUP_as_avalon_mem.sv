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
// Export a platform local_mem interface to an AFU as an Avalon memory.
//
// The "as Avalon" abstraction here allows an AFU to request the memory
// using a particular interface. The platform may offer multiple interfaces
// to the same underlying PR wires, instantiating protocol conversion
// shims as needed.
//

//
// This version of ofs_plat_local_mem_as_avalon_mem works on platforms
// where the native interface is AXI-MM.
//

`include "ofs_plat_if.vh"

module ofs_plat_local_mem_@group@_as_avalon_mem
  #(
    // When non-zero, add a clock crossing to move the AFU interface
    // to the passed in afu_clk.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages, typically for timing.
    parameter ADD_TIMING_REG_STAGES = 0
    )
   (
    // AFU clock and reset must always be passed in, even when ADD_CLOCK_CROSSING
    // is 0. On systems with multiple AFU interfaces, the local memory reset can
    // not be driven globally by soft reset signals. The AFU-specific soft
    // reset bound to the memory is unknown, except to the AFU. afu_reset_n
    // is mapped below to the local memory's clock domain and drives reset
    // of the full stack instantiated here.
    input  logic afu_clk,
    input  logic afu_reset_n,

    // The ports are named "to_fiu" and "to_afu" despite the Avalon
    // to_sink/to_source naming because the PIM port naming is a
    // bus-independent abstraction. At top-level, PIM ports are
    // always to_fiu and to_afu.
    ofs_plat_axi_mem_if.to_sink to_fiu,
    ofs_plat_avalon_mem_if.to_source_clk to_afu
    );

    // Combine AFU soft reset with the FIU local memory reset
    logic fiu_soft_reset_n = 1'b0;
    logic afu_reset_n_in_fiu_clk;

    ofs_plat_prim_clock_crossing_reset soft_reset
       (
        .clk_src(afu_clk),
        .clk_dst(to_fiu.clk),
        .reset_in(afu_reset_n),
        .reset_out(afu_reset_n_in_fiu_clk)
        );

    always @(posedge to_fiu.clk)
    begin
        fiu_soft_reset_n <= to_fiu.reset_n && afu_reset_n_in_fiu_clk;
    end

    logic clk;
    assign clk = (ADD_CLOCK_CROSSING == 0) ? to_fiu.clk : afu_clk;

    logic reset_n = 1'b0;
    always @(posedge clk)
    begin
        reset_n <= (ADD_CLOCK_CROSSING == 0) ? fiu_soft_reset_n : afu_reset_n;
    end

    assign to_afu.clk = clk;
    assign to_afu.reset_n = reset_n;
    assign to_afu.instance_number = to_fiu.instance_number;

    // AXI addresses are byte indices. Avalon are lines. Pad the AXI low
    // address bits with zero.
    localparam ADDR_BYTE_IDX_WIDTH = to_fiu.ADDR_WIDTH - to_afu.ADDR_WIDTH;

    // AXI bursts are 0 based, so one bit smaller than Avalon.
    localparam AXI_BURST_CNT_WIDTH = to_afu.BURST_CNT_WIDTH_ - 1;
    typedef logic [AXI_BURST_CNT_WIDTH-1 : 0] t_axi_burst_cnt;


    //
    // Map the AFU's Avalon memory interface directly to AXI. We will
    // then use the PIM's AXI pipeline for burst mapping and clock
    // crossing.
    //
    ofs_plat_axi_mem_if
      #(
        .ADDR_WIDTH(to_fiu.ADDR_WIDTH_),
        .DATA_WIDTH(to_fiu.DATA_WIDTH_),
        // Avalon burst count of the source, mapped to AXI size
        .BURST_CNT_WIDTH(AXI_BURST_CNT_WIDTH),
        .RID_WIDTH(to_fiu.RID_WIDTH_),
        .WID_WIDTH(to_fiu.WID_WIDTH_),
        .USER_WIDTH(to_afu.USER_WIDTH_),
        .MASKED_SYMBOL_WIDTH(to_fiu.MASKED_SYMBOL_WIDTH_)
        )
      axi_afu_if();

    logic wr_is_sop;
    logic wr_is_eop;

    ofs_plat_prim_burstcount1_sop_tracker
      #(
        .BURST_CNT_WIDTH(to_afu.BURST_CNT_WIDTH)
        )
      afu_bursts
       (
        .clk,
        .reset_n,

        .flit_valid(to_afu.write && !to_afu.waitrequest),
        .burstcount(to_afu.burstcount),

        .sop(wr_is_sop),
        .eop(wr_is_eop)
        );

    always_comb
    begin
        // Simplify waitrequest logic -- just block on any channel. The downstream PIM
        // code keeps the ready signals independent of valid signals, making this safe.
        to_afu.waitrequest = (wr_is_sop && !axi_afu_if.awready) ||
                             !axi_afu_if.wready ||
                             !axi_afu_if.arready;

        // Write address channel
        axi_afu_if.awvalid = to_afu.write && !to_afu.waitrequest && wr_is_sop;
        axi_afu_if.aw = '0;
        axi_afu_if.aw.addr = { to_afu.address, ADDR_BYTE_IDX_WIDTH'(0) };
        axi_afu_if.aw.len = t_axi_burst_cnt'(to_afu.burstcount - 1);
        axi_afu_if.aw.size = $clog2(to_afu.DATA_N_BYTES);
        axi_afu_if.aw.user = to_afu.user;

        // Write data channel
        axi_afu_if.wvalid = to_afu.write && !to_afu.waitrequest;
        axi_afu_if.w = '0;
        axi_afu_if.w.data = to_afu.writedata;
        axi_afu_if.w.strb = to_afu.byteenable;
        axi_afu_if.w.last = wr_is_eop;
        axi_afu_if.w.user = to_afu.user;

        // Read address channel
        axi_afu_if.arvalid = to_afu.read && !to_afu.waitrequest;
        axi_afu_if.ar = '0;
        axi_afu_if.ar.addr = { to_afu.address, ADDR_BYTE_IDX_WIDTH'(0) };
        axi_afu_if.ar.len = t_axi_burst_cnt'(to_afu.burstcount - 1);
        axi_afu_if.ar.size = $clog2(to_afu.DATA_N_BYTES);
        axi_afu_if.ar.user = to_afu.user;

        // Write response
        axi_afu_if.bready = 1'b1;
        to_afu.writeresponsevalid = axi_afu_if.bvalid;
        to_afu.writeresponse = '0;
        to_afu.writeresponseuser = axi_afu_if.b.user;

        // Read response
        axi_afu_if.rready = 1'b1;
        to_afu.readdatavalid = axi_afu_if.rvalid;
        to_afu.readdata = axi_afu_if.r.data;
        to_afu.response = '0;
        to_afu.readresponseuser = axi_afu_if.r.user;
    end


    //
    // Burst mapping, clock crossing, etc.
    //
    ofs_plat_local_mem_@group@_as_axi_mem
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES),
        .SORT_READ_RESPONSES(1),
        .SORT_WRITE_RESPONSES(1)
        )
      param_mapping
       (
        .to_afu(axi_afu_if),
        .to_fiu,
        .afu_clk,
        .afu_reset_n
        );

endmodule // ofs_plat_local_mem_@group@_as_avalon_mem
