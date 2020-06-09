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

`include "ofs_plat_if.vh"

//
// Reconstruct the WLAST flag on a write data stream by monitoring burst
// counts on the WA channel.
//
module ofs_plat_axi_mem_if_fixup_wlast
   (
    ofs_plat_axi_mem_if.to_master mem_master,
    ofs_plat_axi_mem_if.to_slave mem_slave
    );

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_IF_CHECK_PARAMS_MATCH(mem_slave, mem_master)
    // synthesis translate_on

    logic clk;
    assign clk = mem_slave.clk;
    logic reset_n;
    assign reset_n = mem_slave.reset_n;

    // AR, R and B channels are unaffected
    always_comb
    begin
        mem_slave.ar = mem_master.ar;
        mem_slave.arvalid = mem_master.arvalid;
        mem_master.arready = mem_slave.arready;

        mem_master.r = mem_slave.r;
        mem_master.rvalid = mem_slave.rvalid;
        mem_slave.rready = mem_master.rready;

        mem_master.b = mem_slave.b;
        mem_master.bvalid = mem_slave.bvalid;
        mem_slave.bready = mem_master.bready;
    end

    // Instantiate an interface to use the properly sized internal structs
    // as registers.
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_master),
        .DISABLE_CHECKER(1)
        )
        mem_master_reg();

    logic aw_avail, w_avail;
    logic w_sop, w_eop;
    logic [mem_master.T_W_WIDTH-1 : 0] w;

    // Forward next address when both address and data are available and
    // data is the first flit in the burst. This keeps address and data
    // aligned.
    assign mem_slave.awvalid = aw_avail && mem_slave.awready &&
                               w_avail && mem_slave.wready && w_sop;

    // Forward next data in the middle of a burst or when starting a
    // new burst and the address is available.
    assign mem_slave.wvalid = w_avail && mem_slave.wready &&
                              (!w_sop || (aw_avail && mem_slave.awready));

    // Write address
    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(mem_master.T_AW_WIDTH)
        )
      aw_fifo
       (
        .clk,
        .reset_n,

        .enq_data(mem_master.aw),
        .enq_en(mem_master.awvalid && mem_master.awready),
        .notFull(mem_master.awready),

        .first(mem_slave.aw),
        .deq_en(mem_slave.awvalid),
        .notEmpty(aw_avail)
        );

    // Write data
    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(mem_master.T_W_WIDTH)
        )
      w_fifo
       (
        .clk,
        .reset_n,

        .enq_data(mem_master.w),
        .enq_en(mem_master.wvalid && mem_master.wready),
        .notFull(mem_master.wready),

        .first(w),
        .deq_en(mem_slave.wvalid),
        .notEmpty(w_avail)
        );


    always_comb
    begin
        // Setting mem_slave.w to 0 before overwriting the whole field is silly,
        // but works around a bug in QuestaSim that was missing the .last assignment.
        mem_slave.w = '0;
        mem_slave.w = w;
        // All the logic in this module is just to set this bit
        mem_slave.w.last = w_eop;
    end

    // Track EOP/SOP by monitoring burst counts in AW stream. The AW and W
    // streams are always synchronized during the SOP burst.
    ofs_plat_prim_burstcount0_sop_tracker
      #(
        .BURST_CNT_WIDTH(mem_master.BURST_CNT_WIDTH)
        )
      sop_tracker
       (
        .clk,
        .reset_n,
        .flit_valid(mem_slave.wvalid),
        .burstcount(mem_slave.aw.len),
        .sop(w_sop),
        .eop(w_eop)
        );

endmodule // ofs_plat_axi_mem_if_fixup_wlast
