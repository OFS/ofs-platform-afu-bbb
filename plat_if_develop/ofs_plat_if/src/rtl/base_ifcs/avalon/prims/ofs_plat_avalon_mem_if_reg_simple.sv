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

module ofs_plat_avalon_mem_if_reg_simple_impl
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1,
    parameter N_WAITREQUEST_STAGES = N_REG_STAGES,

    // Internal wrapped implementation takes explicit parameters instead of
    // consuming them from the mem_sink interface because some synthesis
    // tools fail to map mem_sink.ADDR_WIDTH to the mem_pipe[] array.
    // The wrapper modules below work around the problem without affecting
    // other modules.
    parameter ADDR_WIDTH,
    parameter DATA_WIDTH,
    parameter BURST_CNT_WIDTH,
    parameter RESPONSE_WIDTH,
    parameter USER_WIDTH
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
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .BURST_CNT_WIDTH(BURST_CNT_WIDTH),
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

endmodule // ofs_plat_avalon_mem_if_reg_simple_impl


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

    ofs_plat_avalon_mem_if_reg_simple_impl
      #(
        .N_REG_STAGES(N_REG_STAGES),
        .N_WAITREQUEST_STAGES(N_WAITREQUEST_STAGES),
        .ADDR_WIDTH(mem_sink.ADDR_WIDTH_),
        .DATA_WIDTH(mem_sink.DATA_WIDTH_),
        .BURST_CNT_WIDTH(mem_sink.BURST_CNT_WIDTH_),
        .RESPONSE_WIDTH(mem_sink.RESPONSE_WIDTH_),
        .USER_WIDTH(mem_sink.USER_WIDTH_)
        )
      r
       (
        .mem_sink(mem_sink),
        .mem_source(mem_source)
        );

endmodule // ofs_plat_avalon_mem_if_reg_simple
