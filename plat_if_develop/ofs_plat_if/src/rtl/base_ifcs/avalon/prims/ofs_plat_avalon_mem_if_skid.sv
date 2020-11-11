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

module ofs_plat_avalon_mem_if_skid
  #(
    // Enable skid (1) or just connect as wires (0)?
    parameter SKID_REQ = 1,
    // Response has no flow control, so just a register is sufficient.
    parameter REG_RSP = 1
    )
   (
    ofs_plat_avalon_mem_if.to_sink mem_sink,
    ofs_plat_avalon_mem_if.to_source mem_source
    );

    logic clk;
    assign clk = mem_source.clk;
    logic reset_n;
    assign reset_n = mem_source.reset_n;

    // synthesis translate_off
    `OFS_PLAT_AVALON_MEM_IF_CHECK_PARAMS_MATCH(mem_sink, mem_source)
    // synthesis translate_on

    generate
        if (SKID_REQ)
        begin : sk_req
            logic mem_req_ready;
            assign mem_source.waitrequest = !mem_req_ready;

            logic mem_req_valid;
            logic req_read, req_write;
            assign mem_sink.read = req_read && mem_req_valid;
            assign mem_sink.write = req_write && mem_req_valid;

            ofs_plat_prim_ready_enable_skid
              #(
                .N_DATA_BITS(mem_source.BURST_CNT_WIDTH_ +
                             mem_source.DATA_WIDTH_ +
                             mem_source.ADDR_WIDTH_ +
                             1 +
                             1 +
                             mem_source.DATA_N_BYTES +
                             mem_source.USER_WIDTH_)
                )
              mem_req_skid
               (
                .clk,
                .reset_n,

                .enable_from_src(mem_source.read || mem_source.write),
                .data_from_src({ mem_source.burstcount,
                                 mem_source.writedata,
                                 mem_source.address,
                                 mem_source.write,
                                 mem_source.read,
                                 mem_source.byteenable,
                                 mem_source.user }),
                .ready_to_src(mem_req_ready),

                .enable_to_dst(mem_req_valid),
                .data_to_dst({ mem_sink.burstcount,
                               mem_sink.writedata,
                               mem_sink.address,
                               req_write,
                               req_read,
                               mem_sink.byteenable,
                               mem_sink.user }),
                .ready_from_dst(!mem_sink.waitrequest)
                );
        end
        else
        begin : c_req
            assign mem_source.waitrequest = mem_sink.waitrequest;
            always_comb
            begin
                `OFS_PLAT_AVALON_MEM_IF_FROM_SOURCE_TO_SINK_COMB(mem_sink, mem_source);
            end
        end

        if (REG_RSP)
        begin : r_rsp
            always_ff @(posedge clk)
            begin
                `OFS_PLAT_AVALON_MEM_IF_FROM_SINK_TO_SOURCE(mem_source, <=, mem_sink);
            end
        end
        else
        begin : c_rsp
            always_comb
            begin
                `OFS_PLAT_AVALON_MEM_IF_FROM_SINK_TO_SOURCE(mem_source, =, mem_sink);
            end
        end
    endgenerate

endmodule // ofs_plat_avalon_mem_if_skid
