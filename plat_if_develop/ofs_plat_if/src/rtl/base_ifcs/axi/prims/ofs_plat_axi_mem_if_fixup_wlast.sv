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
    ofs_plat_axi_mem_if.to_source mem_source,
    ofs_plat_axi_mem_if.to_sink mem_sink
    );

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_IF_CHECK_PARAMS_MATCH(mem_sink, mem_source)
    // synthesis translate_on

    logic clk;
    assign clk = mem_sink.clk;
    logic reset_n;
    assign reset_n = mem_sink.reset_n;

    // AR, R and B channels are unaffected
    always_comb
    begin
        mem_sink.ar = mem_source.ar;
        mem_sink.arvalid = mem_source.arvalid;
        mem_source.arready = mem_sink.arready;

        mem_source.r = mem_sink.r;
        mem_source.rvalid = mem_sink.rvalid;
        mem_sink.rready = mem_source.rready;

        mem_source.b = mem_sink.b;
        mem_source.bvalid = mem_sink.bvalid;
        mem_sink.bready = mem_source.bready;
    end

    // Instantiate an interface to use the properly sized internal structs
    // as registers.
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_source),
        .DISABLE_CHECKER(1)
        )
        mem_source_reg();

    logic aw_avail, w_avail;
    logic w_sop, w_eop;
    logic [mem_source.T_W_WIDTH-1 : 0] w;

    // Forward next address when both address and data are available and
    // data is the first flit in the burst. This keeps address and data
    // aligned.
    assign mem_sink.awvalid = aw_avail && mem_sink.awready &&
                               w_avail && mem_sink.wready && w_sop;

    // Forward next data in the middle of a burst or when starting a
    // new burst and the address is available.
    assign mem_sink.wvalid = w_avail && mem_sink.wready &&
                              (!w_sop || (aw_avail && mem_sink.awready));

    // Write address
    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(mem_source.T_AW_WIDTH)
        )
      aw_fifo
       (
        .clk,
        .reset_n,

        .enq_data(mem_source.aw),
        .enq_en(mem_source.awvalid && mem_source.awready),
        .notFull(mem_source.awready),

        .first(mem_sink.aw),
        .deq_en(mem_sink.awvalid),
        .notEmpty(aw_avail)
        );

    // Write data
    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(mem_source.T_W_WIDTH)
        )
      w_fifo
       (
        .clk,
        .reset_n,

        .enq_data(mem_source.w),
        .enq_en(mem_source.wvalid && mem_source.wready),
        .notFull(mem_source.wready),

        .first(w),
        .deq_en(mem_sink.wvalid),
        .notEmpty(w_avail)
        );


    always_comb
    begin
        // Setting mem_sink.w to 0 before overwriting the whole field is silly,
        // but works around a bug in QuestaSim that was missing the .last assignment.
        mem_sink.w = '0;
        mem_sink.w = w;
        // All the logic in this module is just to set this bit
        mem_sink.w.last = w_eop;
    end

    // Track EOP/SOP by monitoring burst counts in AW stream. The AW and W
    // streams are always synchronized during the SOP burst.
    ofs_plat_prim_burstcount0_sop_tracker
      #(
        .BURST_CNT_WIDTH(mem_source.BURST_CNT_WIDTH)
        )
      sop_tracker
       (
        .clk,
        .reset_n,
        .flit_valid(mem_sink.wvalid),
        .burstcount(mem_sink.aw.len),
        .sop(w_sop),
        .eop(w_eop)
        );

endmodule // ofs_plat_axi_mem_if_fixup_wlast
