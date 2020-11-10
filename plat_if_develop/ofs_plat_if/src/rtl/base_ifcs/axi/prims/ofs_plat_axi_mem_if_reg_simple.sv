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
// A simple version of AXI MM interface register stage insertion.
// The sink-generated ready signals are treated as an almost full
// protocol, with the assumption that the sink end of the connection
// can handle at least as many requests as the depth of the pipeline
// plus the latency of forwarding ready from the sink side to the
// source side.
//
// The source to sink response ready signals are treated normally,
// under the assumption that in a simple protocol sources will
// always be ready.
//

module ofs_plat_axi_mem_if_reg_simple
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1,
    parameter N_READY_STAGES = N_REG_STAGES
    )
   (
    ofs_plat_axi_mem_if.to_sink mem_sink,
    ofs_plat_axi_mem_if.to_source mem_source
    );

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_IF_CHECK_PARAMS_MATCH(mem_sink, mem_source)
    // synthesis translate_on

    genvar s;
    generate
        if (N_REG_STAGES == 0)
        begin : wires
            ofs_plat_axi_mem_if_connect conn(.mem_sink, .mem_source);
        end
        else
        begin : regs
            // Pipeline stages.
            ofs_plat_axi_mem_if
              #(
                `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_sink)
                )
                mem_pipe[N_REG_STAGES+1]();

            // Map mem_sink to stage 0 (wired) to make the for loop below simpler.
            ofs_plat_axi_mem_if_connect_sink_clk
              conn0
               (
                .mem_sink(mem_sink),
                .mem_source(mem_pipe[0])
                );


            // ============================================================
            //
            //  Source to sink buses (almost full protocol)
            //
            // ============================================================

            // Inject the requested number of stages
            for (s = 1; s <= N_REG_STAGES; s = s + 1)
            begin : pms
                assign mem_pipe[s].clk = mem_sink.clk;
                assign mem_pipe[s].reset_n = mem_sink.reset_n;

                always_ff @(posedge mem_sink.clk)
                begin
                    // Sink ready signals are a different pipeline, implemented below.
                    mem_pipe[s].awready <= 1'b1;
                    mem_pipe[s].wready <= 1'b1;
                    mem_pipe[s].arready <= 1'b1;

                    `OFS_PLAT_AXI_MEM_IF_FROM_SOURCE_TO_SINK_FF(mem_pipe[s-1], mem_pipe[s]);

                    if (!mem_sink.reset_n)
                    begin
                        mem_pipe[s-1].awvalid <= 1'b0;
                        mem_pipe[s-1].wvalid <= 1'b0;
                        mem_pipe[s-1].arvalid <= 1'b0;
                    end
                end

                // Debugging signal
                assign mem_pipe[s].instance_number = mem_pipe[s-1].instance_number;
            end


            // Ready signals are shift registers, with mem_sink signals entering
            // at bit 0.
            logic [N_READY_STAGES:0] awready_pipe, wready_pipe;
            logic [N_READY_STAGES:0] arready_pipe;
            assign awready_pipe[0] = mem_sink.awready;
            assign wready_pipe[0] = mem_sink.wready;
            assign arready_pipe[0] = mem_sink.arready;

            always_ff @(posedge mem_sink.clk)
            begin
                // Shift the ready pipelines
                awready_pipe[N_READY_STAGES:1] <=
                    mem_sink.reset_n ? awready_pipe[N_READY_STAGES-1:0] :
                                        {N_READY_STAGES{1'b0}};

                wready_pipe[N_READY_STAGES:1] <=
                    mem_sink.reset_n ? wready_pipe[N_READY_STAGES-1:0] :
                                        {N_READY_STAGES{1'b0}};

                arready_pipe[N_READY_STAGES:1] <=
                    mem_sink.reset_n ? arready_pipe[N_READY_STAGES-1:0] :
                                        {N_READY_STAGES{1'b0}};
            end


            // ============================================================
            //
            //  Sink to source buses (normal ready/enable)
            //
            // ============================================================

            // Build systolic pipelines for sink to source responses
            // under the assumption that modules using the reg_simple primitive
            // are always ready to receive responses.
            for (s = 1; s <= N_REG_STAGES; s = s + 1)
            begin : psm
                ofs_plat_prim_ready_enable_reg
                  #(
                    .N_DATA_BITS($bits(mem_pipe[s].b))
                    )
                  r
                   (
                    .clk(mem_sink.clk),
                    .reset_n(mem_sink.reset_n),

                    .enable_from_src(mem_pipe[s-1].bvalid),
                    .data_from_src(mem_pipe[s-1].b),
                    .ready_to_src(mem_pipe[s-1].bready),

                    .enable_to_dst(mem_pipe[s].bvalid),
                    .data_to_dst(mem_pipe[s].b),
                    .ready_from_dst(mem_pipe[s].bready)
                    );
            end


            // ============================================================
            //
            //  Connect pipeline to the source
            //
            // ============================================================

            // Map mem_source to the last stage (wired)
            always_comb
            begin
                `OFS_PLAT_AXI_MEM_IF_FROM_SOURCE_TO_SINK_COMB(mem_pipe[N_REG_STAGES], mem_source);
                `OFS_PLAT_AXI_MEM_IF_FROM_SINK_TO_SOURCE_COMB(mem_source, mem_pipe[N_REG_STAGES]);

                //
                // Pipelines using almost full use non-standard ready signals.
                //

                mem_source.awready = awready_pipe[N_READY_STAGES];
                mem_pipe[N_REG_STAGES].awvalid = mem_source.awvalid && mem_source.awready;

                mem_source.wready = wready_pipe[N_READY_STAGES];
                mem_pipe[N_REG_STAGES].wvalid = mem_source.wvalid && mem_source.wready;

                mem_source.arready = arready_pipe[N_READY_STAGES];
                mem_pipe[N_REG_STAGES].arvalid = mem_source.arvalid && mem_source.arready;
            end

        end
    endgenerate

endmodule // ofs_plat_axi_mem_if_reg_simple
