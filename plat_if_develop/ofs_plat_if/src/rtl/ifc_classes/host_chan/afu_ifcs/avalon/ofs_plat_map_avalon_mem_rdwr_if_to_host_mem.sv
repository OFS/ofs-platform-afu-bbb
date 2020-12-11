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
// Map an Avalon port to the properties required a host memory port. Maximum
// burst size, alignment and response ordering are all handled here.
// The sink remains in Avalon format. The final, protocol-specific, host
// port conversion is handled outside this module.
//
module ofs_plat_map_avalon_mem_rdwr_if_to_host_mem
  #(
    // When non-zero the source and sink use different clocks.
    parameter ADD_CLOCK_CROSSING = 0,

    // Does the host memory port require natural alignment?
    parameter NATURAL_ALIGNMENT = 0,

    // Does the host memory port require avoiding page crossing?
    parameter PAGE_SIZE = 0,

    // Sizes of the response buffers in the ROB and clock crossing.
    parameter MAX_ACTIVE_RD_LINES = 256,
    parameter MAX_ACTIVE_WR_LINES = 256,

    // When non-zero, the write channel is blocked when the read channel runs
    // out of credits. On some channels, such as PCIe TLP, blocking writes along
    // with reads solves a fairness problem caused by writes not having either
    // tags or completions.
    parameter BLOCK_WRITE_WITH_READ = 0,

    // First bit in the user fields where the ROB indices should be stored.
    parameter USER_ROB_IDX_START = 0
    )
   (
    // mem_source parameters should match the source's field widths.
    ofs_plat_avalon_mem_rdwr_if.to_source mem_source,

    // mem_sink parameters should match the requirements of the host
    // memory port. The user fields should be sized to hold reorder
    // buffer indices for read and write responses.
    ofs_plat_avalon_mem_rdwr_if.to_sink mem_sink
    );

    //
    // Map AFU-sized bursts to FIU-sized bursts. (The AFU may generate larger
    // bursts than the FIU will accept.)
    //
    ofs_plat_avalon_mem_rdwr_if
      #(
        `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_MEM_PARAMS(mem_source),
        .BURST_CNT_WIDTH(mem_sink.BURST_CNT_WIDTH_),
        .USER_WIDTH(mem_source.USER_WIDTH_)
        )
      avmm_fiu_burst_if();

    assign avmm_fiu_burst_if.clk = mem_source.clk;
    assign avmm_fiu_burst_if.reset_n = mem_source.reset_n;
    assign avmm_fiu_burst_if.instance_number = mem_sink.instance_number;

    ofs_plat_avalon_mem_rdwr_if_map_bursts
      #(
        .NATURAL_ALIGNMENT(NATURAL_ALIGNMENT),
        .PAGE_SIZE(PAGE_SIZE)
        )
      map_bursts
       (
        .mem_source(mem_source),
        .mem_sink(avmm_fiu_burst_if)
        );


    //
    // Cross to the FIU clock and add sort responses. The two are combined
    // because the clock crossing buffer can also be used for sorting.
    //
    ofs_plat_avalon_mem_rdwr_if_async_rob
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .MAX_ACTIVE_RD_LINES(MAX_ACTIVE_RD_LINES),
        .MAX_ACTIVE_WR_LINES(MAX_ACTIVE_WR_LINES),
        .USER_ROB_IDX_START(USER_ROB_IDX_START),
        .BLOCK_WRITE_WITH_READ(BLOCK_WRITE_WITH_READ)
        )
      rob
       (
        .mem_source(avmm_fiu_burst_if),
        .mem_sink
        );


    // synthesis translate_off
    always_ff @(negedge mem_source.clk)
    begin
        if (mem_source.reset_n)
        begin
            if (mem_source.wr_write && !mem_source.wr_waitrequest)
            begin
                // Memory fence?
                if ((mem_source.USER_WIDTH > ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_FENCE) &&
                    mem_source.wr_user[ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_FENCE])
                begin
                    if (mem_source.wr_burstcount != 1)
                    begin
                        $fatal(2, "** ERROR ** %m: Memory fence burstcount must be 1!");
                    end
                end
            end
        end
    end
    // synthesis translate_on

endmodule // ofs_plat_map_avalon_mem_rdwr_if_to_host_mem
