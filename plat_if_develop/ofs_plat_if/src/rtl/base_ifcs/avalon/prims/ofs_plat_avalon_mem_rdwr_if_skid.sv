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

`include "ofs_plat_if.vh"

//
// Insert skid buffers on all channels between the two interfaces.
//

module ofs_plat_avalon_mem_rdwr_if_skid
  #(
    // Enable skid (1) or just connect as wires (0)?
    parameter SKID_RD_REQ = 1,
    parameter SKID_WR_REQ = 1,
    // Response has no flow control, so just a register is sufficient.
    parameter REG_RSP = 1
    )
   (
    ofs_plat_avalon_mem_rdwr_if.to_slave mem_slave,
    ofs_plat_avalon_mem_rdwr_if.to_master mem_master
    );

    logic clk;
    assign clk = mem_master.clk;
    logic reset_n;
    assign reset_n = mem_master.reset_n;

    // synthesis translate_off
    `OFS_PLAT_AVALON_MEM_RDWR_IF_CHECK_PARAMS_MATCH(mem_slave, mem_master)
    // synthesis translate_on

    generate
        if (SKID_RD_REQ)
        begin : sk_rd_req
            logic mem_rd_ready;
            assign mem_master.rd_waitrequest = !mem_rd_ready;

            ofs_plat_prim_ready_enable_skid
              #(
                .N_DATA_BITS(mem_master.BURST_CNT_WIDTH_ +
                             mem_master.ADDR_WIDTH_ +
                             mem_master.DATA_N_BYTES +
                             mem_master.USER_WIDTH_)
                )
              mem_rd_skid
               (
                .clk,
                .reset_n,

                .enable_from_src(mem_master.rd_read),
                .data_from_src({ mem_master.rd_burstcount,
                                 mem_master.rd_address,
                                 mem_master.rd_byteenable,
                                 mem_master.rd_user }),
                .ready_to_src(mem_rd_ready),

                .enable_to_dst(mem_slave.rd_read),
                .data_to_dst({ mem_slave.rd_burstcount,
                               mem_slave.rd_address,
                               mem_slave.rd_byteenable,
                               mem_slave.rd_user }),
                .ready_from_dst(!mem_slave.rd_waitrequest)
                );
        end
        else
        begin : c_rd_req
            assign mem_master.rd_waitrequest = mem_slave.rd_waitrequest;
            always_comb
            begin
                `OFS_PLAT_AVALON_MEM_RDWR_IF_RD_FROM_MASTER_TO_SLAVE_COMB(mem_slave, mem_master);
            end
        end

        if (SKID_WR_REQ)
        begin : sk_wr_req
            logic mem_wr_ready;
            assign mem_master.wr_waitrequest = !mem_wr_ready;

            ofs_plat_prim_ready_enable_skid
              #(
                .N_DATA_BITS(mem_master.BURST_CNT_WIDTH_ +
                             mem_master.DATA_WIDTH_ +
                             mem_master.ADDR_WIDTH_ +
                             mem_master.DATA_N_BYTES +
                             mem_master.USER_WIDTH_)
                )
              mem_wr_skid
               (
                .clk,
                .reset_n,

                .enable_from_src(mem_master.wr_write),
                .data_from_src({ mem_master.wr_burstcount,
                                 mem_master.wr_writedata,
                                 mem_master.wr_address,
                                 mem_master.wr_byteenable,
                                 mem_master.wr_user }),
                .ready_to_src(mem_wr_ready),

                .enable_to_dst(mem_slave.wr_write),
                .data_to_dst({ mem_slave.wr_burstcount,
                               mem_slave.wr_writedata,
                               mem_slave.wr_address,
                               mem_slave.wr_byteenable,
                               mem_slave.wr_user }),
                .ready_from_dst(!mem_slave.wr_waitrequest)
                );
        end
        else
        begin : c_wr_req
            assign mem_master.wr_waitrequest = mem_slave.wr_waitrequest;
            always_comb
            begin
                `OFS_PLAT_AVALON_MEM_RDWR_IF_WR_FROM_MASTER_TO_SLAVE_COMB(mem_slave, mem_master);
            end
        end

        if (REG_RSP)
        begin : r_rsp
            always_ff @(posedge clk)
            begin
                `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SLAVE_TO_MASTER(mem_master, <=, mem_slave);
            end
        end
        else
        begin : c_rsp
            always_comb
            begin
                `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_SLAVE_TO_MASTER(mem_master, =, mem_slave);
            end
        end
    endgenerate

endmodule // ofs_plat_avalon_mem_rdwr_if_skid
