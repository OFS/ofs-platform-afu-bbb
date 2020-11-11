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

`include "ofs_plat_if.vh"

//
// A simple version of Avalon MM interface register stage insertion.
// Waitrequest is treated as an almost full protocol, with the assumption
// that the sink end of the connection can handle at least as many
// requests as the depth of the pipeline plus the latency of
// forwarding waitrequest from the sink side to the source side.
//

module ofs_plat_avalon_mem_if_reg_simple
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1,
    parameter N_WAITREQUEST_STAGES = N_REG_STAGES
    )
   (
    ofs_plat_avalon_mem_if.to_sink mem_sink,
    ofs_plat_avalon_mem_if.to_source mem_source
    );

    genvar s;
    generate
        if (N_REG_STAGES == 0)
        begin : wires
            ofs_plat_avalon_mem_if_connect conn(.mem_sink, .mem_source);
        end
        else
        begin : regs
            // Pipeline stages.
            ofs_plat_avalon_mem_if
              #(
                .ADDR_WIDTH(mem_sink.ADDR_WIDTH_),
                .DATA_WIDTH(mem_sink.DATA_WIDTH_),
                .BURST_CNT_WIDTH(mem_sink.BURST_CNT_WIDTH_),
                .WAIT_REQUEST_ALLOWANCE(N_WAITREQUEST_STAGES)
                )
                mem_pipe[N_REG_STAGES+1]();

            // Map mem_sink to stage 0 (wired) to make the for loop below simpler.
            ofs_plat_avalon_mem_if_connect_sink_clk
              conn0
               (
                .mem_sink(mem_sink),
                .mem_source(mem_pipe[0])
                );

            // Inject the requested number of stages
            for (s = 1; s <= N_REG_STAGES; s = s + 1)
            begin : p
                assign mem_pipe[s].clk = mem_sink.clk;
                assign mem_pipe[s].reset_n = mem_sink.reset_n;

                always_ff @(posedge mem_sink.clk)
                begin
                    // Waitrequest is a different pipeline, implemented below.
                    mem_pipe[s].waitrequest <= 1'b1;

                    `OFS_PLAT_AVALON_MEM_IF_FROM_SINK_TO_SOURCE_FF(mem_pipe[s], mem_pipe[s-1]);
                    `OFS_PLAT_AVALON_MEM_IF_FROM_SOURCE_TO_SINK_FF(mem_pipe[s-1], mem_pipe[s]);

                    if (!mem_sink.reset_n)
                    begin
                        mem_pipe[s-1].read <= 1'b0;
                        mem_pipe[s-1].write <= 1'b0;
                    end
                end

                // Debugging signal
                assign mem_pipe[s].instance_number = mem_pipe[s-1].instance_number;
            end


            // waitrequest is a shift register, with mem_sink.waitrequest entering
            // at bit 0.
            logic [N_WAITREQUEST_STAGES:0] mem_waitrequest_pipe;
            assign mem_waitrequest_pipe[0] = mem_sink.waitrequest;

            always_ff @(posedge mem_sink.clk)
            begin
                // Shift the waitrequest pipeline
                mem_waitrequest_pipe[N_WAITREQUEST_STAGES:1] <=
                    mem_sink.reset_n ? mem_waitrequest_pipe[N_WAITREQUEST_STAGES-1:0] :
                                        {N_WAITREQUEST_STAGES{1'b0}};
            end


            // Map mem_source to the last stage (wired)
            always_comb
            begin
                `OFS_PLAT_AVALON_MEM_IF_FROM_SINK_TO_SOURCE_COMB(mem_source, mem_pipe[N_REG_STAGES]);
                mem_source.waitrequest = mem_waitrequest_pipe[N_WAITREQUEST_STAGES];

                `OFS_PLAT_AVALON_MEM_IF_FROM_SOURCE_TO_SINK_COMB(mem_pipe[N_REG_STAGES], mem_source);
                mem_pipe[N_REG_STAGES].read = mem_source.read && ! mem_source.waitrequest;
                mem_pipe[N_REG_STAGES].write = mem_source.write && ! mem_source.waitrequest;
            end
        end
    endgenerate

endmodule // ofs_plat_avalon_mem_if_reg_simple
