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

//
// Add a configurable number of pipeline stages between a pair of AXI
// memory interface objects.  Pipeline stages are complex because of the
// ready/enable protocol.
//

`include "ofs_plat_if.vh"

module ofs_plat_axi_mem_if_reg
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1
    )
   (
    ofs_plat_axi_mem_if.to_slave mem_slave,
    ofs_plat_axi_mem_if.to_master mem_master
    );

    // synthesis translate_off
    `OFS_PLAT_AXI_MEM_IF_CHECK_PARAMS_MATCH(mem_slave, mem_master)
    // synthesis translate_on

    genvar s;
    generate
        if (N_REG_STAGES == 0)
        begin : wires
            ofs_plat_axi_mem_if_connect conn(.mem_slave, .mem_master);
        end
        else
        begin : regs
            // Pipeline stages.
            ofs_plat_axi_mem_if
              #(
                `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_slave)
                )
                mem_pipe[N_REG_STAGES+1]();

            // Map mem_slave to stage 0 (wired) to make the for loop below simpler.
            ofs_plat_axi_mem_if_connect_slave_clk
              conn0
               (
                .mem_slave(mem_slave),
                .mem_master(mem_pipe[0])
                );

            // Inject the requested number of stages
            for (s = 1; s <= N_REG_STAGES; s = s + 1)
            begin : p
                assign mem_pipe[s].clk = mem_slave.clk;
                assign mem_pipe[s].reset_n = mem_slave.reset_n;

                // Each of the 5 buses is a separate ready/enable bus

                ofs_plat_prim_ready_enable_fifo
                  #(
                    .N_DATA_BITS(mem_slave.T_AW_WIDTH)
                    )
                  aw
                   (
                    .clk(mem_slave.clk),
                    .reset_n(mem_slave.reset_n),

                    .enable_from_src(mem_pipe[s].awvalid),
                    .data_from_src(mem_pipe[s].aw),
                    .ready_to_src(mem_pipe[s].awready),

                    .enable_to_dst(mem_pipe[s-1].awvalid),
                    .data_to_dst(mem_pipe[s-1].aw),
                    .ready_from_dst(mem_pipe[s-1].awready)
                    );

                ofs_plat_prim_ready_enable_fifo
                  #(
                    .N_DATA_BITS(mem_slave.T_W_WIDTH)
                    )
                  w
                   (
                    .clk(mem_slave.clk),
                    .reset_n(mem_slave.reset_n),

                    .enable_from_src(mem_pipe[s].wvalid),
                    .data_from_src(mem_pipe[s].w),
                    .ready_to_src(mem_pipe[s].wready),

                    .enable_to_dst(mem_pipe[s-1].wvalid),
                    .data_to_dst(mem_pipe[s-1].w),
                    .ready_from_dst(mem_pipe[s-1].wready)
                    );

                ofs_plat_prim_ready_enable_fifo
                  #(
                    .N_DATA_BITS(mem_slave.T_B_WIDTH)
                    )
                  b
                   (
                    .clk(mem_slave.clk),
                    .reset_n(mem_slave.reset_n),

                    .enable_from_src(mem_pipe[s-1].bvalid),
                    .data_from_src(mem_pipe[s-1].b),
                    .ready_to_src(mem_pipe[s-1].bready),

                    .enable_to_dst(mem_pipe[s].bvalid),
                    .data_to_dst(mem_pipe[s].b),
                    .ready_from_dst(mem_pipe[s].bready)
                    );

                ofs_plat_prim_ready_enable_fifo
                  #(
                    .N_DATA_BITS(mem_slave.T_AR_WIDTH)
                    )
                  ar
                   (
                    .clk(mem_slave.clk),
                    .reset_n(mem_slave.reset_n),

                    .enable_from_src(mem_pipe[s].arvalid),
                    .data_from_src(mem_pipe[s].ar),
                    .ready_to_src(mem_pipe[s].arready),

                    .enable_to_dst(mem_pipe[s-1].arvalid),
                    .data_to_dst(mem_pipe[s-1].ar),
                    .ready_from_dst(mem_pipe[s-1].arready)
                    );

                ofs_plat_prim_ready_enable_fifo
                  #(
                    .N_DATA_BITS(mem_slave.T_R_WIDTH)
                    )
                  r
                   (
                    .clk(mem_slave.clk),
                    .reset_n(mem_slave.reset_n),

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

            // Map mem_master to the last stage (wired)
            ofs_plat_axi_mem_if_connect conn1(.mem_slave(mem_pipe[N_REG_STAGES]),
                                              .mem_master(mem_master));
        end
    endgenerate

endmodule // ofs_plat_axi_mem_if_reg


// Same as standard connection, but pass clk and reset from slave to master
module ofs_plat_axi_mem_if_reg_slave_clk
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1
    )
   (
    ofs_plat_axi_mem_if.to_slave mem_slave,
    ofs_plat_axi_mem_if.to_master_clk mem_master
    );

    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_slave)
        )
      mem_reg();

    assign mem_reg.clk = mem_slave.clk;
    assign mem_reg.reset_n = mem_slave.reset_n;
    // Debugging signal
    assign mem_reg.instance_number = mem_slave.instance_number;

    ofs_plat_axi_mem_if_reg
      #(
        .N_REG_STAGES(N_REG_STAGES)
        )
      conn_reg
       (
        .mem_slave(mem_slave),
        .mem_master(mem_reg)
        );

    ofs_plat_axi_mem_if_connect_slave_clk
      conn_direct
       (
        .mem_slave(mem_reg),
        .mem_master(mem_master)
        );

endmodule // ofs_plat_axi_mem_if_reg_slave_clk


// Same as standard connection, but pass clk and reset from master to slave
module ofs_plat_axi_mem_if_reg_master_clk
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1
    )
   (
    ofs_plat_axi_mem_if.to_slave_clk mem_slave,
    ofs_plat_axi_mem_if.to_master mem_master
    );

    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_slave)
        )
      mem_reg();

    assign mem_reg.clk = mem_master.clk;
    assign mem_reg.reset_n = mem_master.reset_n;
    // Debugging signal
    assign mem_reg.instance_number = mem_master.instance_number;

    ofs_plat_axi_mem_if_reg
      #(
        .N_REG_STAGES(N_REG_STAGES)
        )
      conn_reg
       (
        .mem_slave(mem_reg),
        .mem_master(mem_master)
        );

    ofs_plat_axi_mem_if_connect_master_clk
      conn_direct
       (
        .mem_slave(mem_slave),
        .mem_master(mem_reg)
        );

endmodule // ofs_plat_axi_mem_if_reg_master_clk
