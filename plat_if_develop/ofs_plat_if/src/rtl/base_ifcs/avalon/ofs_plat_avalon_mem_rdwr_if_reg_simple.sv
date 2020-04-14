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
// that the slave end of the connection can handle at least as many
// requests as the depth of the pipeline plus the latency of
// forwarding waitrequest from the slave side to the master side.
//

module ofs_plat_avalon_mem_rdwr_if_reg_simple
  #(
    // Number of stages to add when registering inputs or outputs
    parameter N_REG_STAGES = 1,
    parameter N_WAITREQUEST_STAGES = N_REG_STAGES
    )
   (
    ofs_plat_avalon_mem_rdwr_if.to_slave mem_slave,
    ofs_plat_avalon_mem_rdwr_if.to_master mem_master
    );

    genvar s;
    generate
        if (N_REG_STAGES == 0)
        begin : wires
            ofs_plat_avalon_mem_rdwr_if_connect conn(.mem_slave, .mem_master);
        end
        else
        begin : regs
            // Pipeline stages.
            ofs_plat_avalon_mem_rdwr_if
              #(
                .ADDR_WIDTH(mem_slave.ADDR_WIDTH_),
                .DATA_WIDTH(mem_slave.DATA_WIDTH_),
                .BURST_CNT_WIDTH(mem_slave.BURST_CNT_WIDTH_),
                .WAIT_REQUEST_ALLOWANCE(N_WAITREQUEST_STAGES)
                )
                mem_pipe[N_REG_STAGES+1]();

            // Map mem_slave to stage 0 (wired) to make the for loop below simpler.
            ofs_plat_avalon_mem_rdwr_if_connect_slave_clk
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

                always_ff @(posedge mem_slave.clk)
                begin
                    // Waitrequest is a different pipeline, implemented below.
                    mem_pipe[s].rd_waitrequest <= 1'b1;
                    mem_pipe[s].wr_waitrequest <= 1'b1;

                    `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SLAVE_TO_MASTER_FF(mem_pipe[s], mem_pipe[s-1]);
                    `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_MASTER_TO_SLAVE_FF(mem_pipe[s-1], mem_pipe[s]);

                    if (!mem_slave.reset_n)
                    begin
                        mem_pipe[s-1].rd_read <= 1'b0;
                        mem_pipe[s-1].wr_write <= 1'b0;
                    end
                end

                // Debugging signal
                assign mem_pipe[s].instance_number = mem_pipe[s-1].instance_number;
            end


            // waitrequest is a shift register, with mem_slave.waitrequest entering
            // at bit 0.
            logic [N_WAITREQUEST_STAGES:0] mem_rd_waitrequest_pipe;
            assign mem_rd_waitrequest_pipe[0] = mem_slave.rd_waitrequest;
            logic [N_WAITREQUEST_STAGES:0] mem_wr_waitrequest_pipe;
            assign mem_wr_waitrequest_pipe[0] = mem_slave.wr_waitrequest;

            always_ff @(posedge mem_slave.clk)
            begin
                // Shift the waitrequest pipeline
                mem_rd_waitrequest_pipe[N_WAITREQUEST_STAGES:1] <=
                    mem_slave.reset_n ? mem_rd_waitrequest_pipe[N_WAITREQUEST_STAGES-1:0] :
                                        {N_WAITREQUEST_STAGES{1'b0}};

                mem_wr_waitrequest_pipe[N_WAITREQUEST_STAGES:1] <=
                    mem_slave.reset_n ? mem_wr_waitrequest_pipe[N_WAITREQUEST_STAGES-1:0] :
                                        {N_WAITREQUEST_STAGES{1'b0}};
            end


            // Map mem_master to the last stage (wired)
            always_comb
            begin
                `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SLAVE_TO_MASTER_COMB(mem_master, mem_pipe[N_REG_STAGES]);
                mem_master.rd_waitrequest = mem_rd_waitrequest_pipe[N_WAITREQUEST_STAGES];
                mem_master.wr_waitrequest = mem_wr_waitrequest_pipe[N_WAITREQUEST_STAGES];

                `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_MASTER_TO_SLAVE_COMB(mem_pipe[N_REG_STAGES], mem_master);
                mem_pipe[N_REG_STAGES].rd_read = mem_master.rd_read && ! mem_master.rd_waitrequest;
                mem_pipe[N_REG_STAGES].wr_write = mem_master.wr_write && ! mem_master.wr_waitrequest;
            end
        end
    endgenerate

endmodule // ofs_plat_avalon_mem_rdwr_if_reg_simple
