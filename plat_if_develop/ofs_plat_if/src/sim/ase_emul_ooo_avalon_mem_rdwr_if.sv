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
// Emulate an out of order Avalon port by swapping the order of responses randomly.
//

`include "ofs_plat_if.vh"

module ase_emul_ooo_avalon_mem_rdwr_if
  #(
    // Are responses out of order?
    parameter OUT_OF_ORDER = 0
    )
   (
    ofs_plat_avalon_mem_rdwr_if.to_slave mem_slave,
    ofs_plat_avalon_mem_rdwr_if.to_master_clk mem_master
    );
            
    localparam DATA_WIDTH = mem_slave.DATA_WIDTH_;
    localparam RESPONSE_WIDTH = mem_slave.RESPONSE_WIDTH_;
    localparam USER_WIDTH = mem_slave.USER_WIDTH_;

    generate
        if (OUT_OF_ORDER == 0)
        begin : n
            // Not out of order
            ofs_plat_avalon_mem_rdwr_if_connect_slave_clk conn
               (
                .mem_slave,
                .mem_master
                );
        end
        else
        begin : o
            assign mem_master.clk = mem_slave.clk;
            assign mem_master.reset_n = mem_slave.reset_n;
            assign mem_master.instance_number = mem_slave.instance_number;

            always_comb
            begin
                `OFS_PLAT_AVALON_MEM_RDWR_IF_FROM_MASTER_TO_SLAVE_COMB(mem_slave, mem_master);

                mem_master.rd_waitrequest = mem_slave.rd_waitrequest;
                mem_master.wr_waitrequest = mem_slave.wr_waitrequest;
            end

            ase_emul_ooo_pipe
              #(
                .DATA_WIDTH(DATA_WIDTH + RESPONSE_WIDTH + USER_WIDTH + 1)
                )
              rd_ooo
               (
                .clk(mem_slave.clk),
                .reset_n(mem_slave.reset_n),
                .data_in({ mem_slave.rd_readdata,
                           mem_slave.rd_response,
                           mem_slave.rd_readresponseuser,
                           mem_slave.rd_readdatavalid }),
                .data_out({ mem_master.rd_readdata,
                            mem_master.rd_response,
                            mem_master.rd_readresponseuser,
                            mem_master.rd_readdatavalid })
                );

            ase_emul_ooo_pipe
              #(
                .DATA_WIDTH(RESPONSE_WIDTH + USER_WIDTH + 1)
                )
              wr_ooo
               (
                .clk(mem_slave.clk),
                .reset_n(mem_slave.reset_n),
                .data_in({ mem_slave.wr_response,
                           mem_slave.wr_writeresponseuser,
                           mem_slave.wr_writeresponsevalid }),
                .data_out({ mem_master.wr_response,
                            mem_master.wr_writeresponseuser,
                            mem_master.wr_writeresponsevalid })
                );
        end
    endgenerate

endmodule // ase_emul_ooo_avalon_mem_rdwr_if


module ase_emul_ooo_pipe
  #(
    parameter DATA_WIDTH = 0
    )
   (
    input  logic clk,
    input  logic reset_n,
    input  logic [DATA_WIDTH-1 : 0] data_in,
    output logic [DATA_WIDTH-1 : 0] data_out
    );

    // Rotate "random" number generator
    logic [19:0] rnd;
    always_ff @(posedge clk)
    begin
        rnd <= { rnd[18:0], rnd[19] };

        if (!reset_n)
        begin
            rnd <= 20'h8676d;
        end
    end

    // There is no flow control. Keep data_in flowing into the queue, replacing
    // either q0 or q1 randomly.

    typedef logic [DATA_WIDTH-1 : 0] t_data;
    t_data q0, q1;

    always_ff @(posedge clk)
    begin
        if (rnd[0])
        begin
            q0 <= data_in;
            data_out <= q0;
        end
        else
        begin
            q1 <= data_in;
            data_out <= q1;
        end

        if (!reset_n)
        begin
            q0[0] <= 1'b0;
            q1[0] <= 1'b0;
            data_out[0] <= 1'b0;
        end
    end

endmodule // ase_emul_ooo_pipe
