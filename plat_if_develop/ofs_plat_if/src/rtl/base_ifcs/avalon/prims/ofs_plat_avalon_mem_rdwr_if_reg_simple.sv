// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// A simple version of Avalon MM interface register stage insertion.
// Waitrequest is treated as an almost full protocol, with the assumption
// that the sink end of the connection can handle at least as many
// requests as the depth of the pipeline plus the latency of
// forwarding waitrequest from the sink side to the source side.
//

module ofs_plat_avalon_mem_rdwr_if_reg_simple
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1,
    parameter N_WAITREQUEST_STAGES = N_REG_STAGES
    )
   (
    ofs_plat_avalon_mem_rdwr_if.to_sink mem_sink,
    ofs_plat_avalon_mem_rdwr_if.to_source mem_source
    );

    genvar s;
    generate
        if (N_REG_STAGES == 0)
        begin : wires
            ofs_plat_avalon_mem_rdwr_if_connect conn(.mem_sink, .mem_source);
        end
        else
        begin : regs
            // Pipeline stages.
            ofs_plat_avalon_mem_rdwr_if
              #(
                .ADDR_WIDTH(mem_sink.ADDR_WIDTH),
                .DATA_WIDTH(mem_sink.DATA_WIDTH),
                .BURST_CNT_WIDTH(mem_sink.BURST_CNT_WIDTH),
                .WAIT_REQUEST_ALLOWANCE(N_WAITREQUEST_STAGES)
                )
                mem_pipe[N_REG_STAGES+1]();

            // Map mem_sink to stage 0 (wired) to make the for loop below simpler.
            ofs_plat_avalon_mem_rdwr_if_connect_sink_clk
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
                    mem_pipe[s].rd_waitrequest <= 1'b1;
                    mem_pipe[s].wr_waitrequest <= 1'b1;

                    `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SINK_TO_SOURCE_FF(mem_pipe[s], mem_pipe[s-1]);
                    `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SOURCE_TO_SINK_FF(mem_pipe[s-1], mem_pipe[s]);

                    if (!mem_sink.reset_n)
                    begin
                        mem_pipe[s-1].rd_read <= 1'b0;
                        mem_pipe[s-1].wr_write <= 1'b0;
                    end
                end

                // Debugging signal
                assign mem_pipe[s].instance_number = mem_pipe[s-1].instance_number;
            end


            // waitrequest is a shift register, with mem_sink.waitrequest entering
            // at bit 0.
            logic [N_WAITREQUEST_STAGES:0] mem_rd_waitrequest_pipe;
            assign mem_rd_waitrequest_pipe[0] = mem_sink.rd_waitrequest;
            logic [N_WAITREQUEST_STAGES:0] mem_wr_waitrequest_pipe;
            assign mem_wr_waitrequest_pipe[0] = mem_sink.wr_waitrequest;

            always_ff @(posedge mem_sink.clk)
            begin
                // Shift the waitrequest pipeline
                mem_rd_waitrequest_pipe[N_WAITREQUEST_STAGES:1] <=
                    mem_sink.reset_n ? mem_rd_waitrequest_pipe[N_WAITREQUEST_STAGES-1:0] :
                                        {N_WAITREQUEST_STAGES{1'b0}};

                mem_wr_waitrequest_pipe[N_WAITREQUEST_STAGES:1] <=
                    mem_sink.reset_n ? mem_wr_waitrequest_pipe[N_WAITREQUEST_STAGES-1:0] :
                                        {N_WAITREQUEST_STAGES{1'b0}};
            end


            // Map mem_source to the last stage (wired)
            always_comb
            begin
                `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SINK_TO_SOURCE_COMB(mem_source, mem_pipe[N_REG_STAGES]);
                mem_source.rd_waitrequest = mem_rd_waitrequest_pipe[N_WAITREQUEST_STAGES];
                mem_source.wr_waitrequest = mem_wr_waitrequest_pipe[N_WAITREQUEST_STAGES];

                `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SOURCE_TO_SINK_COMB(mem_pipe[N_REG_STAGES], mem_source);
                mem_pipe[N_REG_STAGES].rd_read = mem_source.rd_read && ! mem_source.rd_waitrequest;
                mem_pipe[N_REG_STAGES].wr_write = mem_source.wr_write && ! mem_source.wr_waitrequest;
            end
        end
    endgenerate

endmodule // ofs_plat_avalon_mem_rdwr_if_reg_simple
