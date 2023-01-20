// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Add a configurable number of pipeline stages between a pair of AXI
// memory interface objects.  Pipeline stages are complex because of the
// ready/enable protocol.
//

`include "ofs_plat_if.vh"

module ofs_plat_axi_mem_lite_if_reg_impl
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1,

    parameter ADDR_WIDTH,
    parameter DATA_WIDTH,
    parameter RID_WIDTH,
    parameter WID_WIDTH,
    parameter USER_WIDTH,

    parameter T_AW_WIDTH,
    parameter T_W_WIDTH,
    parameter T_B_WIDTH,
    parameter T_AR_WIDTH,
    parameter T_R_WIDTH
    )
   (
    ofs_plat_axi_mem_lite_if.to_sink mem_sink,
    ofs_plat_axi_mem_lite_if.to_source mem_source
    );

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_LITE_IF_CHECK_PARAMS_MATCH(mem_sink, mem_source)
    // synthesis translate_on

    genvar s;
    generate
        if (N_REG_STAGES == 0)
        begin : wires
            ofs_plat_axi_mem_lite_if_connect conn(.mem_sink, .mem_source);
        end
        else
        begin : regs
            // Pipeline stages.
            ofs_plat_axi_mem_lite_if
              #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .RID_WIDTH(RID_WIDTH),
                .WID_WIDTH(WID_WIDTH),
                .USER_WIDTH(USER_WIDTH)
                )
                mem_pipe[N_REG_STAGES+1]();

            // Map mem_sink to stage 0 (wired) to make the for loop below simpler.
            ofs_plat_axi_mem_lite_if_connect_sink_clk
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

                // Each of the 5 buses is a separate ready/enable bus

                ofs_plat_prim_ready_enable_skid
                  #(
                    .N_DATA_BITS(T_AW_WIDTH)
                    )
                  aw
                   (
                    .clk(mem_sink.clk),
                    .reset_n(mem_sink.reset_n),

                    .enable_from_src(mem_pipe[s].awvalid),
                    .data_from_src(mem_pipe[s].aw),
                    .ready_to_src(mem_pipe[s].awready),

                    .enable_to_dst(mem_pipe[s-1].awvalid),
                    .data_to_dst(mem_pipe[s-1].aw),
                    .ready_from_dst(mem_pipe[s-1].awready)
                    );

                ofs_plat_prim_ready_enable_skid
                  #(
                    .N_DATA_BITS(T_W_WIDTH)
                    )
                  w
                   (
                    .clk(mem_sink.clk),
                    .reset_n(mem_sink.reset_n),

                    .enable_from_src(mem_pipe[s].wvalid),
                    .data_from_src(mem_pipe[s].w),
                    .ready_to_src(mem_pipe[s].wready),

                    .enable_to_dst(mem_pipe[s-1].wvalid),
                    .data_to_dst(mem_pipe[s-1].w),
                    .ready_from_dst(mem_pipe[s-1].wready)
                    );

                ofs_plat_prim_ready_enable_skid
                  #(
                    .N_DATA_BITS(T_B_WIDTH)
                    )
                  b
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

                ofs_plat_prim_ready_enable_skid
                  #(
                    .N_DATA_BITS(T_AR_WIDTH)
                    )
                  ar
                   (
                    .clk(mem_sink.clk),
                    .reset_n(mem_sink.reset_n),

                    .enable_from_src(mem_pipe[s].arvalid),
                    .data_from_src(mem_pipe[s].ar),
                    .ready_to_src(mem_pipe[s].arready),

                    .enable_to_dst(mem_pipe[s-1].arvalid),
                    .data_to_dst(mem_pipe[s-1].ar),
                    .ready_from_dst(mem_pipe[s-1].arready)
                    );

                ofs_plat_prim_ready_enable_skid
                  #(
                    .N_DATA_BITS(T_R_WIDTH)
                    )
                  r
                   (
                    .clk(mem_sink.clk),
                    .reset_n(mem_sink.reset_n),

                    .enable_from_src(mem_pipe[s-1].rvalid),
                    .data_from_src(mem_pipe[s-1].r),
                    .ready_to_src(mem_pipe[s-1].rready),

                    .enable_to_dst(mem_pipe[s].rvalid),
                    .data_to_dst(mem_pipe[s].r),
                    .ready_from_dst(mem_pipe[s].rready)
                    );


                // Debugging signal
                assign mem_pipe[s].instance_number = mem_pipe[s-1].instance_number;
            end

            // Map mem_source to the last stage (wired)
            ofs_plat_axi_mem_lite_if_connect conn1(.mem_sink(mem_pipe[N_REG_STAGES]),
                                                   .mem_source(mem_source));
        end
    endgenerate

endmodule // ofs_plat_axi_mem_lite_if_reg_impl


module ofs_plat_axi_mem_lite_if_reg
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1
    )
   (
    ofs_plat_axi_mem_lite_if.to_sink mem_sink,
    ofs_plat_axi_mem_lite_if.to_source mem_source
    );

    ofs_plat_axi_mem_lite_if_reg_impl
      #(
        .N_REG_STAGES(N_REG_STAGES),
        .ADDR_WIDTH(mem_sink.ADDR_WIDTH_),
        .DATA_WIDTH(mem_sink.DATA_WIDTH_),
        .RID_WIDTH(mem_sink.RID_WIDTH_),
        .WID_WIDTH(mem_sink.WID_WIDTH_),
        .USER_WIDTH(mem_sink.USER_WIDTH_),

        .T_AW_WIDTH(mem_sink.T_AW_WIDTH),
        .T_W_WIDTH(mem_sink.T_W_WIDTH),
        .T_B_WIDTH(mem_sink.T_B_WIDTH),
        .T_AR_WIDTH(mem_sink.T_AR_WIDTH),
        .T_R_WIDTH(mem_sink.T_R_WIDTH)
        )
      r
       (
        .mem_sink(mem_sink),
        .mem_source(mem_source)
        );

endmodule // ofs_plat_axi_mem_lite_if_reg


// Same as standard connection, but pass clk and reset from sink to source
module ofs_plat_axi_mem_lite_if_reg_sink_clk
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1
    )
   (
    ofs_plat_axi_mem_lite_if.to_sink mem_sink,
    ofs_plat_axi_mem_lite_if.to_source_clk mem_source
    );

    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mem_sink)
        )
      mem_reg();

    assign mem_reg.clk = mem_sink.clk;
    assign mem_reg.reset_n = mem_sink.reset_n;
    // Debugging signal
    assign mem_reg.instance_number = mem_sink.instance_number;

    ofs_plat_axi_mem_lite_if_reg
      #(
        .N_REG_STAGES(N_REG_STAGES)
        )
      conn_reg
       (
        .mem_sink(mem_sink),
        .mem_source(mem_reg)
        );

    ofs_plat_axi_mem_lite_if_connect_sink_clk
      conn_direct
       (
        .mem_sink(mem_reg),
        .mem_source(mem_source)
        );

endmodule // ofs_plat_axi_mem_lite_if_reg_sink_clk


// Same as standard connection, but pass clk and reset from source to sink
module ofs_plat_axi_mem_lite_if_reg_source_clk
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1
    )
   (
    ofs_plat_axi_mem_lite_if.to_sink_clk mem_sink,
    ofs_plat_axi_mem_lite_if.to_source mem_source
    );

    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(mem_sink)
        )
      mem_reg();

    assign mem_reg.clk = mem_source.clk;
    assign mem_reg.reset_n = mem_source.reset_n;
    // Debugging signal
    assign mem_reg.instance_number = mem_source.instance_number;

    ofs_plat_axi_mem_lite_if_reg
      #(
        .N_REG_STAGES(N_REG_STAGES)
        )
      conn_reg
       (
        .mem_sink(mem_reg),
        .mem_source(mem_source)
        );

    ofs_plat_axi_mem_lite_if_connect_source_clk
      conn_direct
       (
        .mem_sink(mem_sink),
        .mem_source(mem_reg)
        );

endmodule // ofs_plat_axi_mem_lite_if_reg_source_clk
