// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Add a configurable number of pipeline stages between a pair of Avalon
// memory interface objects.  Pipeline stages are complex because of the
// waitrequest protocol.
//

`include "ofs_plat_if.vh"

module ofs_plat_avalon_mem_if_reg_impl
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1,

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
                .USER_WIDTH(USER_WIDTH)
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

                ofs_plat_utils_avalon_mm_bridge
                  #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .HDL_ADDR_WIDTH(USER_WIDTH + ADDR_WIDTH),
                    .BURSTCOUNT_WIDTH(BURST_CNT_WIDTH),
                    .RESPONSE_WIDTH(USER_WIDTH + RESPONSE_WIDTH)
                    )
                  bridge
                   (
                    .clk(mem_pipe[s].clk),
                    .reset(!mem_pipe[s].reset_n),

                    .s0_waitrequest(mem_pipe[s].waitrequest),
                    .s0_readdata(mem_pipe[s].readdata),
                    .s0_readdatavalid(mem_pipe[s].readdatavalid),
                    // Write response handled separately, below
                    .s0_writeresponsevalid(),
                    .s0_response({ mem_pipe[s].readresponseuser,
                                   mem_pipe[s].response }),
                    .s0_burstcount(mem_pipe[s].burstcount),
                    .s0_writedata(mem_pipe[s].writedata),
                    .s0_address({ mem_pipe[s].user,
                                  mem_pipe[s].address }),
                    .s0_write(mem_pipe[s].write), 
                    .s0_read(mem_pipe[s].read), 
                    .s0_byteenable(mem_pipe[s].byteenable), 
                    .s0_debugaccess(1'b0),

                    .m0_waitrequest(mem_pipe[s - 1].waitrequest),
                    .m0_readdata(mem_pipe[s - 1].readdata),
                    .m0_readdatavalid(mem_pipe[s - 1].readdatavalid),
                    .m0_writeresponsevalid(1'b0),
                    .m0_response({ mem_pipe[s - 1].readresponseuser,
                                   mem_pipe[s - 1].response }),
                    .m0_burstcount(mem_pipe[s - 1].burstcount),
                    .m0_writedata(mem_pipe[s - 1].writedata),
                    .m0_address({ mem_pipe[s - 1].user,
                                  mem_pipe[s - 1].address }),
                    .m0_write(mem_pipe[s - 1].write), 
                    .m0_read(mem_pipe[s - 1].read), 
                    .m0_byteenable(mem_pipe[s - 1].byteenable),
                    .m0_debugaccess()
                    );

                // The Avalon bridge doesn't handle a separate write response bus.
                always_ff @(posedge mem_sink.clk)
                begin
                    mem_pipe[s].writeresponsevalid <= mem_pipe[s - 1].writeresponsevalid;
                    mem_pipe[s].writeresponse <= mem_pipe[s - 1].writeresponse;
                    mem_pipe[s].writeresponseuser <= mem_pipe[s - 1].writeresponseuser;
                end

                // Debugging signal
                assign mem_pipe[s].instance_number = mem_pipe[s-1].instance_number;
            end

            // Map mem_source to the last stage (wired)
            ofs_plat_avalon_mem_if_connect conn1(.mem_sink(mem_pipe[N_REG_STAGES]),
                                                 .mem_source(mem_source));
        end
    endgenerate

endmodule // ofs_plat_avalon_mem_if_reg_impl


module ofs_plat_avalon_mem_if_reg
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1
    )
   (
    ofs_plat_avalon_mem_if.to_sink mem_sink,
    ofs_plat_avalon_mem_if.to_source mem_source
    );

    ofs_plat_avalon_mem_if_reg_impl
      #(
        .N_REG_STAGES(N_REG_STAGES),
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

endmodule // ofs_plat_avalon_mem_if_reg


// Same as standard connection, but pass clk and reset_n from sink to source
module ofs_plat_avalon_mem_if_reg_sink_clk
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1
    )
   (
    ofs_plat_avalon_mem_if.to_sink mem_sink,
    ofs_plat_avalon_mem_if.to_source_clk mem_source
    );

    ofs_plat_avalon_mem_if
      #(
        .ADDR_WIDTH(mem_sink.ADDR_WIDTH_),
        .DATA_WIDTH(mem_sink.DATA_WIDTH_),
        .BURST_CNT_WIDTH(mem_sink.BURST_CNT_WIDTH_),
        .USER_WIDTH(mem_sink.USER_WIDTH_)
        )
      mem_reg();

    assign mem_reg.clk = mem_sink.clk;
    assign mem_reg.reset_n = mem_sink.reset_n;
    // Debugging signal
    assign mem_reg.instance_number = mem_sink.instance_number;

    ofs_plat_avalon_mem_if_reg
      #(
        .N_REG_STAGES(N_REG_STAGES)
        )
      conn_reg
       (
        .mem_sink(mem_sink),
        .mem_source(mem_reg)
        );

    ofs_plat_avalon_mem_if_connect_sink_clk
      conn_direct
       (
        .mem_sink(mem_reg),
        .mem_source(mem_source)
        );

endmodule // ofs_plat_avalon_mem_if_reg_sink_clk


// Same as standard connection, but pass clk and reset_n from source to sink
module ofs_plat_avalon_mem_if_reg_source_clk
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1
    )
   (
    ofs_plat_avalon_mem_if.to_sink_clk mem_sink,
    ofs_plat_avalon_mem_if.to_source mem_source
    );

    ofs_plat_avalon_mem_if
      #(
        .ADDR_WIDTH(mem_sink.ADDR_WIDTH_),
        .DATA_WIDTH(mem_sink.DATA_WIDTH_),
        .BURST_CNT_WIDTH(mem_sink.BURST_CNT_WIDTH_),
        .USER_WIDTH(mem_sink.USER_WIDTH_)
        )
      mem_reg();

    assign mem_reg.clk = mem_source.clk;
    assign mem_reg.reset_n = mem_source.reset_n;
    // Debugging signal
    assign mem_reg.instance_number = mem_source.instance_number;

    ofs_plat_avalon_mem_if_reg
      #(
        .N_REG_STAGES(N_REG_STAGES)
        )
      conn_reg
       (
        .mem_sink(mem_reg),
        .mem_source(mem_source)
        );

    ofs_plat_avalon_mem_if_connect_source_clk
      conn_direct
       (
        .mem_sink(mem_sink),
        .mem_source(mem_reg)
        );

endmodule // ofs_plat_avalon_mem_if_reg_source_clk
