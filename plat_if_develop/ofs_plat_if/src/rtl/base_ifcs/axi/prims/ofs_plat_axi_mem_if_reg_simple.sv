// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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

module ofs_plat_axi_mem_if_reg_simple_impl
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1,
    parameter N_READY_STAGES = N_REG_STAGES,

    // Internal wrapped implementation takes explicit parameters instead of
    // consuming them from the mem_sink interface because some synthesis
    // tools fail to map mem_sink.ADDR_WIDTH to the mem_pipe[] array.
    // The wrapper modules below work around the problem without affecting
    // other modules.
    parameter ADDR_WIDTH,
    parameter DATA_WIDTH,
    parameter BURST_CNT_WIDTH,
    parameter RID_WIDTH,
    parameter WID_WIDTH,
    parameter USER_WIDTH
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
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .BURST_CNT_WIDTH(BURST_CNT_WIDTH),
                .RID_WIDTH(RID_WIDTH),
                .WID_WIDTH(WID_WIDTH),
                .USER_WIDTH(USER_WIDTH)
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

endmodule // ofs_plat_axi_mem_if_reg_simple_impl


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

    ofs_plat_axi_mem_if_reg_simple_impl
      #(
        .N_REG_STAGES(N_REG_STAGES),
        .N_READY_STAGES(N_READY_STAGES),
        .ADDR_WIDTH(mem_sink.ADDR_WIDTH),
        .DATA_WIDTH(mem_sink.DATA_WIDTH),
        .BURST_CNT_WIDTH(mem_sink.BURST_CNT_WIDTH),
        .RID_WIDTH(mem_sink.RID_WIDTH),
        .WID_WIDTH(mem_sink.WID_WIDTH),
        .USER_WIDTH(mem_sink.USER_WIDTH)
        )
      r
       (
        .mem_sink(mem_sink),
        .mem_source(mem_source)
        );

endmodule // ofs_plat_axi_mem_if_reg_simple
