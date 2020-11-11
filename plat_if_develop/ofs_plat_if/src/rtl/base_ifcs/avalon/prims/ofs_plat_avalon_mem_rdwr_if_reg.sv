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

//
// Add a configurable number of pipeline stages between a pair of Avalon
// split bus read write memory interface objects.  Pipeline stages are
// complex because of the waitrequest protocol.
//

`include "ofs_plat_if.vh"

module ofs_plat_avalon_mem_rdwr_if_reg
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1
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
            // Pass user extension fields through the pipeline
            localparam USER_WIDTH = mem_sink.USER_WIDTH_;

            // Pipeline stages.
            ofs_plat_avalon_mem_rdwr_if
              #(
                `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS(mem_sink)
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

                ofs_plat_utils_avalon_mm_bridge
                  #(
                    .DATA_WIDTH(mem_sink.DATA_WIDTH),
                    .HDL_ADDR_WIDTH(USER_WIDTH + mem_sink.ADDR_WIDTH),
                    .BURSTCOUNT_WIDTH(mem_sink.BURST_CNT_WIDTH),
                    .RESPONSE_WIDTH(USER_WIDTH + mem_sink.RESPONSE_WIDTH)
                    )
                  bridge_rd
                   (
                    .clk(mem_pipe[s].clk),
                    .reset(!mem_pipe[s].reset_n),

                    .s0_waitrequest(mem_pipe[s].rd_waitrequest),
                    .s0_readdata(mem_pipe[s].rd_readdata),
                    .s0_readdatavalid(mem_pipe[s].rd_readdatavalid),
                    .s0_response({ mem_pipe[s].rd_readresponseuser,
                                   mem_pipe[s].rd_response }),
                    .s0_burstcount(mem_pipe[s].rd_burstcount),
                    .s0_writedata('0),
                    .s0_address({ mem_pipe[s].rd_user,
                                  mem_pipe[s].rd_address }),
                    .s0_write(1'b0),
                    .s0_read(mem_pipe[s].rd_read),
                    .s0_byteenable(mem_pipe[s].rd_byteenable),
                    .s0_debugaccess(1'b0),

                    .m0_waitrequest(mem_pipe[s - 1].rd_waitrequest),
                    .m0_readdata(mem_pipe[s - 1].rd_readdata),
                    .m0_readdatavalid(mem_pipe[s - 1].rd_readdatavalid),
                    .m0_response({ mem_pipe[s - 1].rd_readresponseuser,
                                   mem_pipe[s - 1].rd_response }),
                    .m0_burstcount(mem_pipe[s - 1].rd_burstcount),
                    .m0_writedata(),
                    .m0_address({ mem_pipe[s - 1].rd_user,
                                  mem_pipe[s - 1].rd_address }),
                    .m0_write(),
                    .m0_read(mem_pipe[s - 1].rd_read),
                    .m0_byteenable(mem_pipe[s - 1].rd_byteenable),
                    .m0_debugaccess()
                    );

                ofs_plat_utils_avalon_mm_bridge
                  #(
                    .DATA_WIDTH(mem_sink.DATA_WIDTH),
                    .HDL_ADDR_WIDTH(USER_WIDTH + mem_sink.ADDR_WIDTH),
                    .BURSTCOUNT_WIDTH(mem_sink.BURST_CNT_WIDTH),
                    .RESPONSE_WIDTH(USER_WIDTH + mem_sink.RESPONSE_WIDTH)
                    )
                  bridge_wr
                   (
                    .clk(mem_pipe[s].clk),
                    .reset(!mem_pipe[s].reset_n),

                    .s0_waitrequest(mem_pipe[s].wr_waitrequest),
                    .s0_readdata(),
                    // Use readdatavalid/response to pass write response.
                    // The bridge doesn't count reads or writes, so this works.
                    .s0_readdatavalid(mem_pipe[s].wr_writeresponsevalid),
                    .s0_response({ mem_pipe[s].wr_writeresponseuser,
                                   mem_pipe[s].wr_response }),
                    .s0_burstcount(mem_pipe[s].wr_burstcount),
                    .s0_writedata(mem_pipe[s].wr_writedata),
                    .s0_address({ mem_pipe[s].wr_user,
                                  mem_pipe[s].wr_address }),
                    .s0_write(mem_pipe[s].wr_write),
                    .s0_read(1'b0),
                    .s0_byteenable(mem_pipe[s].wr_byteenable),
                    .s0_debugaccess(1'b0),

                    .m0_waitrequest(mem_pipe[s - 1].wr_waitrequest),
                    .m0_readdata('0),
                    // See above -- readdatavalid is used for write responses
                    .m0_readdatavalid(mem_pipe[s - 1].wr_writeresponsevalid),
                    .m0_response({ mem_pipe[s - 1].wr_writeresponseuser,
                                   mem_pipe[s - 1].wr_response }),
                    .m0_burstcount(mem_pipe[s - 1].wr_burstcount),
                    .m0_writedata(mem_pipe[s - 1].wr_writedata),
                    .m0_address({ mem_pipe[s - 1].wr_user,
                                  mem_pipe[s - 1].wr_address }),
                    .m0_write(mem_pipe[s - 1].wr_write),
                    .m0_read(),
                    .m0_byteenable(mem_pipe[s - 1].wr_byteenable),
                    .m0_debugaccess()
                    );

                // Debugging signal
                assign mem_pipe[s].instance_number = mem_pipe[s-1].instance_number;
            end

            // Map mem_source to the last stage (wired)
            ofs_plat_avalon_mem_rdwr_if_connect conn1(.mem_sink(mem_pipe[N_REG_STAGES]),
                                                      .mem_source(mem_source));
        end
    endgenerate

endmodule // ofs_plat_avalon_mem_rdwr_if_reg


// Same as standard connection, but pass clk and reset_n from sink to source
module ofs_plat_avalon_mem_rdwr_if_reg_sink_clk
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1
    )
   (
    ofs_plat_avalon_mem_rdwr_if.to_sink mem_sink,
    ofs_plat_avalon_mem_rdwr_if.to_source_clk mem_source
    );

    ofs_plat_avalon_mem_rdwr_if
      #(
        `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS(mem_sink)
        )
      mem_reg();

    assign mem_reg.clk = mem_sink.clk;
    assign mem_reg.reset_n = mem_sink.reset_n;
    // Debugging signal
    assign mem_reg.instance_number = mem_sink.instance_number;

    ofs_plat_avalon_mem_rdwr_if_reg
      #(
        .N_REG_STAGES(N_REG_STAGES)
        )
      conn_reg
       (
        .mem_sink(mem_sink),
        .mem_source(mem_reg)
        );

    ofs_plat_avalon_mem_rdwr_if_connect_sink_clk
      conn_direct
       (
        .mem_sink(mem_reg),
        .mem_source(mem_source)
        );

endmodule // ofs_plat_avalon_mem_rdwr_if_reg_sink_clk


// Same as standard connection, but pass clk and reset_n from source to sink
module ofs_plat_avalon_mem_rdwr_if_reg_source_clk
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1
    )
   (
    ofs_plat_avalon_mem_rdwr_if.to_sink_clk mem_sink,
    ofs_plat_avalon_mem_rdwr_if.to_source mem_source
    );

    ofs_plat_avalon_mem_rdwr_if
      #(
        `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS(mem_sink)
        )
      mem_reg();

    assign mem_reg.clk = mem_source.clk;
    assign mem_reg.reset_n = mem_source.reset_n;
    // Debugging signal
    assign mem_reg.instance_number = mem_source.instance_number;

    ofs_plat_avalon_mem_rdwr_if_reg
      #(
        .N_REG_STAGES(N_REG_STAGES)
        )
      conn_reg
       (
        .mem_sink(mem_reg),
        .mem_source(mem_source)
        );

    ofs_plat_avalon_mem_rdwr_if_connect_source_clk
      conn_direct
       (
        .mem_sink(mem_sink),
        .mem_source(mem_reg)
        );

endmodule // ofs_plat_avalon_mem_rdwr_if_reg_source_clk
