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
// Clock crossing bridge for the Avalon memory interface.
//

`include "ofs_plat_if.vh"

module ofs_plat_avalon_mem_if_async_shim
  #(
    parameter COMMAND_FIFO_DEPTH = 128,
    parameter RESPONSE_FIFO_DEPTH = 256,
    // When non-zero, set the command buffer such that COMMAND_ALMFULL_THRESHOLD
    // requests can be received after mem_source.waitrequest is asserted.
    parameter COMMAND_ALMFULL_THRESHOLD = 0,
    parameter PRESERVE_WR_RESP = 1
    )
   (
    ofs_plat_avalon_mem_if.to_sink mem_sink,
    ofs_plat_avalon_mem_if.to_source mem_source
    );

    // Convert resets to active high
    (* preserve *) logic sink_reset0 = 1'b1;
    (* preserve *) logic sink_reset = 1'b1;
    always @(posedge mem_sink.clk)
    begin
        sink_reset0 <= !mem_sink.reset_n;
        sink_reset <= sink_reset0;
    end

    (* preserve *) logic source_reset0 = 1'b1;
    (* preserve *) logic source_reset = 1'b1;
    always @(posedge mem_source.clk)
    begin
        source_reset0 <= !mem_source.reset_n;
        source_reset <= source_reset0;
    end

    localparam SPACE_AVAIL_WIDTH = $clog2(COMMAND_FIFO_DEPTH) + 1;

    logic cmd_waitrequest;
    logic [SPACE_AVAIL_WIDTH-1:0] cmd_space_avail;

    typedef logic [1:0] t_response;
    t_response m0_response_dummy;

    localparam USER_WIDTH = mem_sink.USER_WIDTH;
    typedef logic [USER_WIDTH-1 : 0] t_user;
    t_user m0_user_dummy;

    logic [((USER_WIDTH + $bits(t_response) + mem_sink.DATA_WIDTH) / 8) - 1 : 0] m0_byteenable;

    ofs_plat_utils_avalon_mm_clock_crossing_bridge
      #(
        // Leave room for passing "response" along with readdata
        .DATA_WIDTH(USER_WIDTH + $bits(t_response) + mem_sink.DATA_WIDTH),
        .HDL_ADDR_WIDTH(USER_WIDTH + mem_sink.ADDR_WIDTH),
        .BURSTCOUNT_WIDTH(mem_sink.BURST_CNT_WIDTH),
        .COMMAND_FIFO_DEPTH(COMMAND_FIFO_DEPTH),
        .RESPONSE_FIFO_DEPTH(RESPONSE_FIFO_DEPTH)
        )
      avmm_cross
       (
        .s0_clk(mem_source.clk),
        .s0_reset(source_reset),

        .m0_clk(mem_sink.clk),
        .m0_reset(sink_reset),

        .s0_waitrequest(cmd_waitrequest),
        .s0_readdata({ mem_source.readresponseuser, mem_source.response, mem_source.readdata }),
        .s0_readdatavalid(mem_source.readdatavalid),
        .s0_burstcount(mem_source.burstcount),
        // Write data width has space for response because DATA_WIDTH was set above
        // in order to pass response with readdata.
        .s0_writedata({ t_user'(0), t_response'(0), mem_source.writedata }),
        .s0_address({ mem_source.user, mem_source.address }),
        .s0_write(mem_source.write),
        .s0_read(mem_source.read),
        .s0_byteenable({ '0, mem_source.byteenable }),
        .s0_debugaccess(1'b0),
        .s0_space_avail_data(cmd_space_avail),

        .m0_waitrequest(mem_sink.waitrequest),
        .m0_readdata({ mem_sink.readresponseuser, mem_sink.response, mem_sink.readdata }),
        .m0_readdatavalid(mem_sink.readdatavalid),
        .m0_burstcount(mem_sink.burstcount),
        // See s0_writedata above for m0_response_dummy explanation.
        .m0_writedata({ m0_user_dummy, m0_response_dummy, mem_sink.writedata }),
        .m0_address({ mem_sink.user, mem_sink.address }),
        .m0_write(mem_sink.write),
        .m0_read(mem_sink.read),
        .m0_byteenable(m0_byteenable),
        .m0_debugaccess()
        );

    assign mem_sink.byteenable = m0_byteenable[mem_sink.DATA_WIDTH / 8 - 1 : 0];

    //
    // The standard Avalon clock crossing bridge doesn't pass write responses.
    // Use a simple dual clock FIFO. Since the data in the FIFO is quite narrow
    // and the number of writes in flight is fixed by controller queues, we
    // don't count available queue slots and assume that the FIFO will never
    // overflow.
    //
    generate
        if (PRESERVE_WR_RESP)
        begin : wr_rsp
            logic wr_response_valid;

            ofs_plat_prim_fifo_dc
              #(
                .N_DATA_BITS(USER_WIDTH + $bits(t_response)),
                .N_ENTRIES(1024)
                )
              avmm_cross_wr_response
               (
                .enq_clk(mem_sink.clk),
                .enq_reset_n(mem_sink.reset_n),
                .enq_data({ mem_sink.writeresponseuser, mem_sink.writeresponse }),
                .enq_en(mem_sink.writeresponsevalid),
                .notFull(),
                .almostFull(),

                .deq_clk(mem_source.clk),
                .deq_reset_n(mem_source.reset_n),
                .first({ mem_source.writeresponseuser, mem_source.writeresponse }),
                .deq_en(wr_response_valid),
                .notEmpty(wr_response_valid)
                );

            assign mem_source.writeresponsevalid = wr_response_valid && mem_source.reset_n;
        end
        else
        begin : n_wr_rsp
            assign mem_source.writeresponsevalid = 1'b0;
            assign mem_source.writeresponse = '0;
            assign mem_source.writeresponseuser = '0;
        end
    endgenerate


    // Compute mem_source.waitrequest
    generate
        if (COMMAND_ALMFULL_THRESHOLD == 0)
        begin : no_almfull
            // Use the usual Avalon MM protocol
            assign mem_source.waitrequest = cmd_waitrequest;
        end
        else
        begin : almfull
            // Treat waitrequest as an almost full signal, allowing
            // COMMAND_ALMFULL_THRESHOLD requests after waitrequest is
            // asserted.
            always_ff @(posedge mem_source.clk)
            begin
                if (!mem_source.reset_n)
                begin
                    mem_source.waitrequest <= 1'b1;
                end
                else
                begin
                    mem_source.waitrequest <= cmd_waitrequest ||
                        (cmd_space_avail <= (SPACE_AVAIL_WIDTH)'(COMMAND_ALMFULL_THRESHOLD));
                end
            end

            // synthesis translate_off
            always @(negedge mem_source.clk)
            begin
                // In almost full mode it is illegal for a request to arrive
                // when s0_waitrequest is asserted. If this ever happens it
                // means the almost full protocol has failed and that
                // cmd_space_avail forced back-pressure too late or it was
                // ignored.

                if (mem_source.reset_n && cmd_waitrequest && mem_source.write)
                begin
                    $fatal(2, "** ERROR ** %m: instance %0d dropped write transaction",
                           mem_source.instance_number);
                end

                if (mem_source.reset_n && cmd_waitrequest && mem_source.read)
                begin
                    $fatal(2, "** ERROR ** %m: instance %0d dropped read transaction",
                           mem_source.instance_number);
                end
            end
            // synthesis translate_on
        end
    endgenerate

endmodule // ofs_plat_avalon_mem_if_async_shim


// Same as standard crossing, but set the sink's clock
module ofs_plat_avalon_mem_if_async_shim_set_sink
  #(
    parameter COMMAND_FIFO_DEPTH = 128,
    parameter RESPONSE_FIFO_DEPTH = 256,
    // When non-zero, set the command buffer such that COMMAND_ALMFULL_THRESHOLD
    // requests can be received after mem_source.waitrequest is asserted.
    parameter COMMAND_ALMFULL_THRESHOLD = 0,
    parameter PRESERVE_WR_RESP = 1
    )
   (
    ofs_plat_avalon_mem_if.to_sink_clk mem_sink,
    ofs_plat_avalon_mem_if.to_source mem_source,

    input  logic sink_clk,
    input  logic sink_reset_n
    );

    ofs_plat_avalon_mem_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(mem_sink)
        )
      mem_sink_with_clk();

    assign mem_sink_with_clk.clk = sink_clk;
    assign mem_sink_with_clk.reset_n = sink_reset_n;
    assign mem_sink_with_clk.instance_number = mem_source.instance_number;

    ofs_plat_avalon_mem_if_connect_source_clk con_sink
       (
        .mem_source(mem_sink_with_clk),
        .mem_sink
        );

    ofs_plat_avalon_mem_if_async_shim
      #(
        .COMMAND_FIFO_DEPTH(COMMAND_FIFO_DEPTH),
        .RESPONSE_FIFO_DEPTH(RESPONSE_FIFO_DEPTH),
        .COMMAND_ALMFULL_THRESHOLD(COMMAND_ALMFULL_THRESHOLD),
        .PRESERVE_WR_RESP(PRESERVE_WR_RESP)
        )
      cc
       (
        .mem_sink(mem_sink_with_clk),
        .mem_source
        );

endmodule // ofs_plat_avalon_mem_if_async_shim_set_sink
