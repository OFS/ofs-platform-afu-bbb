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
// Synchronize channels to simplify the AXI interface, making the AXI request
// channels behave more like Avalon. The AW and SOP on W are guaranteed to
// arrive simultaneously.
//
// *** SOP tracking only works if the sink consumes both AW and W when AW
// *** is valid.
//

module ofs_plat_axi_mem_if_sync
   (
    ofs_plat_axi_mem_if.to_sink mem_sink,
    ofs_plat_axi_mem_if.to_source mem_source
    );

    logic clk;
    assign clk = mem_source.clk;
    logic reset_n;
    assign reset_n = mem_source.reset_n;

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_IF_CHECK_PARAMS_MATCH(mem_sink, mem_source)
    // synthesis translate_on

    // Track write stream SOP. AW is allowed only on SOP.
    logic wr_is_sop;
    always_ff @(posedge clk)
    begin
        if (mem_source.wready && mem_source.wvalid)
        begin
            wr_is_sop <= mem_source.w.last;
        end

        if (!reset_n)
        begin
            wr_is_sop <= 1'b1;
        end
    end

    always_comb
    begin
        mem_sink.awvalid = mem_source.awvalid && mem_source.wvalid && wr_is_sop;
        mem_source.awready = mem_sink.awready && mem_source.wvalid && wr_is_sop;
        mem_sink.aw = mem_source.aw;

        mem_sink.wvalid = mem_source.wvalid && (mem_source.awvalid || !wr_is_sop);
        mem_source.wready = mem_sink.wready && (mem_source.awvalid || !wr_is_sop);
        mem_sink.w = mem_source.w;

        mem_sink.arvalid = mem_source.arvalid;
        mem_source.arready = mem_sink.arready;
        mem_sink.ar = mem_source.ar;

        mem_source.bvalid = mem_sink.bvalid;
        mem_sink.bready = mem_source.bready;
        mem_source.b = mem_sink.b;

        mem_source.rvalid = mem_sink.rvalid;
        mem_sink.rready = mem_source.rready;
        mem_source.r = mem_sink.r;
    end

endmodule // ofs_plat_axi_mem_if_sync
