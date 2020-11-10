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
// Clock crossing bridge for the Avalon split bus read write memory interface.
//

module ofs_plat_avalon_mem_rdwr_if_async_shim
  #(
    // When non-zero, set the command buffer such that COMMAND_ALMFULL_THRESHOLD
    // requests can be received after mem_source.waitrequest is asserted.
    parameter COMMAND_ALMFULL_THRESHOLD = 0,

    parameter RD_COMMAND_FIFO_DEPTH = 8 + COMMAND_ALMFULL_THRESHOLD,
    parameter RD_RESPONSE_FIFO_DEPTH = 8,

    parameter WR_COMMAND_FIFO_DEPTH = 8 + COMMAND_ALMFULL_THRESHOLD,
    parameter WR_RESPONSE_FIFO_DEPTH = 8
    )
   (
    ofs_plat_avalon_mem_rdwr_if.to_sink mem_sink,
    ofs_plat_avalon_mem_rdwr_if.to_source mem_source
    );

    localparam RD_SPACE_AVAIL_WIDTH = $clog2(RD_COMMAND_FIFO_DEPTH) + 1;
    localparam WR_SPACE_AVAIL_WIDTH = $clog2(WR_COMMAND_FIFO_DEPTH) + 1;

    logic cmd_rd_waitrequest, cmd_wr_waitrequest;
    logic [RD_SPACE_AVAIL_WIDTH-1:0] cmd_rd_space_avail;
    logic [WR_SPACE_AVAIL_WIDTH-1:0] cmd_wr_space_avail;

    typedef logic [1:0] t_response;
    t_response m0_response_dummy;

    // The clock crossing bridge requires that an extra 2 * MAX_BURST slots
    // remain in the response queue in order to deal with the the depth
    // of the request pipeline inside the clock crossing FIFO. When the
    // maximum burst count is large this can affect throughput. Pad the
    // response FIFO with extra slots.
    localparam RD_MAX_BURST = (1 << (mem_sink.BURST_CNT_WIDTH_ - 1));
    localparam RD_RESPONSE_PADDED_FIFO_DEPTH = RD_RESPONSE_FIFO_DEPTH +
                                               2 * RD_MAX_BURST;

    //
    // Read bus clock crossing
    //
    ofs_plat_utils_avalon_mm_clock_crossing_bridge
      #(
        // Leave room for passing "response" along with readdata
        .DATA_WIDTH($bits(t_response) + mem_sink.DATA_WIDTH),
        .HDL_ADDR_WIDTH(mem_sink.USER_WIDTH + mem_sink.ADDR_WIDTH),
        .BURSTCOUNT_WIDTH(mem_sink.BURST_CNT_WIDTH),
        .COMMAND_FIFO_DEPTH(RD_COMMAND_FIFO_DEPTH),
        .RESPONSE_FIFO_DEPTH(RD_RESPONSE_PADDED_FIFO_DEPTH)
        )
      avmm_cross_rd
       (
        .s0_clk(mem_source.clk),
        .s0_reset(!mem_source.reset_n),

        .m0_clk(mem_sink.clk),
        .m0_reset(!mem_sink.reset_n),

        .s0_waitrequest(cmd_rd_waitrequest),
        .s0_readdata({mem_source.rd_response, mem_source.rd_readdata}),
        .s0_readdatavalid(mem_source.rd_readdatavalid),
        .s0_burstcount(mem_source.rd_burstcount),
        .s0_writedata('0),
        .s0_address({mem_source.rd_user, mem_source.rd_address}),
        .s0_write(1'b0),
        .s0_read(mem_source.rd_read),
        .s0_byteenable(mem_source.rd_byteenable),
        .s0_debugaccess(1'b0),
        .s0_space_avail_data(cmd_rd_space_avail),

        .m0_waitrequest(mem_sink.rd_waitrequest),
        .m0_readdata({mem_sink.rd_response, mem_sink.rd_readdata}),
        .m0_readdatavalid(mem_sink.rd_readdatavalid),
        .m0_burstcount(mem_sink.rd_burstcount),
        .m0_writedata(),
        .m0_address({mem_sink.rd_user, mem_sink.rd_address}),
        .m0_write(),
        .m0_read(mem_sink.rd_read),
        .m0_byteenable(mem_sink.rd_byteenable),
        .m0_debugaccess()
        );

    //
    // Write bus clock crossing
    //
    ofs_plat_utils_avalon_mm_clock_crossing_bridge
      #(
        .DATA_WIDTH(mem_sink.DATA_WIDTH),
        .HDL_ADDR_WIDTH(mem_sink.USER_WIDTH + mem_sink.ADDR_WIDTH),
        .BURSTCOUNT_WIDTH(mem_sink.BURST_CNT_WIDTH),
        .COMMAND_FIFO_DEPTH(WR_COMMAND_FIFO_DEPTH),
        .RESPONSE_FIFO_DEPTH(WR_RESPONSE_FIFO_DEPTH)
        )
      avmm_cross_wr
       (
        .s0_clk(mem_source.clk),
        .s0_reset(!mem_source.reset_n),

        .m0_clk(mem_sink.clk),
        .m0_reset(!mem_sink.reset_n),

        .s0_waitrequest(cmd_wr_waitrequest),
        .s0_readdata(),
        .s0_readdatavalid(),
        .s0_burstcount(mem_source.wr_burstcount),
        .s0_writedata(mem_source.wr_writedata),
        .s0_address({mem_source.wr_user, mem_source.wr_address}),
        .s0_write(mem_source.wr_write),
        .s0_read(1'b0),
        .s0_byteenable(mem_source.wr_byteenable),
        .s0_debugaccess(1'b0),
        .s0_space_avail_data(cmd_wr_space_avail),

        .m0_waitrequest(mem_sink.wr_waitrequest),
        .m0_readdata('0),
        .m0_readdatavalid(1'b0),
        .m0_burstcount(mem_sink.wr_burstcount),
        .m0_writedata(mem_sink.wr_writedata),
        .m0_address({mem_sink.wr_user, mem_sink.wr_address}),
        .m0_write(mem_sink.wr_write),
        .m0_read(),
        .m0_byteenable(mem_sink.wr_byteenable),
        .m0_debugaccess()
        );

    //
    // The standard Avalon clock crossing bridge doesn't pass write responses.
    // Use a simple dual clock FIFO. Since the data in the FIFO is quite narrow
    // and the number of writes in flight is fixed by controller queues, we
    // don't count available queue slots and assume that the FIFO will never
    // overflow.
    //
    logic wr_response_valid;

    ofs_plat_prim_fifo_dc
      #(
        .N_DATA_BITS($bits(t_response)),
        .N_ENTRIES(1024)
        )
      avmm_cross_wr_response
       (
        .enq_clk(mem_sink.clk),
        .enq_reset_n(mem_sink.reset_n),
        .enq_data(mem_sink.wr_response),
        .enq_en(mem_sink.wr_writeresponsevalid),
        .notFull(),
        .almostFull(),

        .deq_clk(mem_source.clk),
        .deq_reset_n(mem_source.reset_n),
        .first(mem_source.wr_response),
        .deq_en(wr_response_valid),
        .notEmpty(wr_response_valid)
        );

    always_ff @(posedge mem_source.clk)
    begin
        mem_source.wr_writeresponsevalid <= wr_response_valid && mem_source.reset_n;
    end


    // Compute mem_source.waitrequest
    generate
        if (COMMAND_ALMFULL_THRESHOLD == 0)
        begin : no_almfull
            // Use the usual Avalon MM protocol
            assign mem_source.rd_waitrequest = cmd_rd_waitrequest;
            assign mem_source.wr_waitrequest = cmd_wr_waitrequest;
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
                    mem_source.rd_waitrequest <= 1'b1;
                    mem_source.wr_waitrequest <= 1'b1;
                end
                else
                begin
                    mem_source.rd_waitrequest <= cmd_rd_waitrequest ||
                        (cmd_rd_space_avail <= (RD_SPACE_AVAIL_WIDTH)'(COMMAND_ALMFULL_THRESHOLD));
                    mem_source.wr_waitrequest <= cmd_wr_waitrequest ||
                        (cmd_wr_space_avail <= (WR_SPACE_AVAIL_WIDTH)'(COMMAND_ALMFULL_THRESHOLD));
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

                if (mem_source.reset_n && cmd_wr_waitrequest && mem_source.wr_write)
                begin
                    $fatal(2, "** ERROR ** %m: instance %0d dropped write transaction",
                           mem_source.instance_number);
                end

                if (mem_source.reset_n && cmd_rd_waitrequest && mem_source.rd_read)
                begin
                    $fatal(2, "** ERROR ** %m: instance %0d dropped read transaction",
                           mem_source.instance_number);
                end
            end
            // synthesis translate_on
        end
    endgenerate

endmodule // ofs_plat_avalon_mem_rdwr_if_async_shim
