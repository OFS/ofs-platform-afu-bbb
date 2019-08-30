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

module ofs_plat_avalon_mem_if_async_shim
  #(
    parameter COMMAND_FIFO_DEPTH = 128,
    // When non-zero, set the command buffer such that COMMAND_ALMFULL_THRESHOLD
    // requests can be received after mem_master.waitrequest is asserted.
    parameter COMMAND_ALMFULL_THRESHOLD = 0
    )
   (
    ofs_plat_avalon_mem_if.to_slave mem_slave,
    ofs_plat_avalon_mem_if.to_master mem_master,
    input  logic mem_master_clk,
    input  logic mem_master_reset
    );

    localparam SPACE_AVAIL_WIDTH = $clog2(COMMAND_FIFO_DEPTH) + 1;

    logic cmd_waitrequest;
    logic [SPACE_AVAIL_WIDTH-1:0] cmd_space_avail;

    assign mem_master.clk = mem_master_clk;
    assign mem_master.reset = mem_master_reset;

    ofs_plat_utils_avalon_mm_clock_crossing_bridge
      #(
        .DATA_WIDTH(mem_slave.DATA_WIDTH),
        .HDL_ADDR_WIDTH(mem_slave.ADDR_WIDTH),
        .BURSTCOUNT_WIDTH(mem_slave.BURST_CNT_WIDTH),
        .COMMAND_FIFO_DEPTH(COMMAND_FIFO_DEPTH),
        .RESPONSE_FIFO_DEPTH(2 ** (mem_slave.BURST_CNT_WIDTH + 1))
        )
      avmm_cross
       (
        .s0_clk(mem_master.clk),
        .s0_reset(mem_master.reset),

        .m0_clk(mem_slave.clk),
        .m0_reset(mem_slave.reset),

        .s0_waitrequest(cmd_waitrequest),
        .s0_readdata(mem_master.readdata),
        .s0_readdatavalid(mem_master.readdatavalid),
        .s0_burstcount(mem_master.burstcount),
        .s0_writedata(mem_master.writedata),
        .s0_address(mem_master.address),
        .s0_write(mem_master.write),
        .s0_read(mem_master.read),
        .s0_byteenable(mem_master.byteenable),
        .s0_debugaccess(1'b0),
        .s0_space_avail_data(cmd_space_avail),

        .m0_waitrequest(mem_slave.waitrequest),
        .m0_readdata(mem_slave.readdata),
        .m0_readdatavalid(mem_slave.readdatavalid),
        .m0_burstcount(mem_slave.burstcount),
        .m0_writedata(mem_slave.writedata),
        .m0_address(mem_slave.address),
        .m0_write(mem_slave.write),
        .m0_read(mem_slave.read),
        .m0_byteenable(mem_slave.byteenable),
        .m0_debugaccess()
        );

    // response doesn't pass through the bridge. It isn't supported.
    assign mem_master.response = 'x;

    // writeresponsevalid does not pass through the bridge. Synthesize it here.
    ofs_plat_avalon_mem_if_gen_write_response
      #(
        .BURST_CNT_WIDTH(mem_master.BURST_CNT_WIDTH)
        )
      wr_resp
       (
        .clk(mem_master.clk),
        .reset(mem_master.reset),

        .write(mem_master.write),
        .waitrequest(mem_master.waitrequest),
        .burstcount(mem_master.burstcount),

        .writeresponsevalid(mem_master.writeresponsevalid)
        );

    // Compute mem_master.waitrequest
    generate
        if (COMMAND_ALMFULL_THRESHOLD == 0)
        begin : no_almfull
            // Use the usual Avalon MM protocol
            assign mem_master.waitrequest = cmd_waitrequest;
        end
        else
        begin : almfull
            // Treat waitrequest as an almost full signal, allowing
            // COMMAND_ALMFULL_THRESHOLD requests after waitrequest is
            // asserted.
            always_ff @(posedge mem_master.clk)
            begin
                if (mem_master.reset)
                begin
                    mem_master.waitrequest <= 1'b1;
                end
                else
                begin
                    mem_master.waitrequest <= cmd_waitrequest ||
                        (cmd_space_avail <= (SPACE_AVAIL_WIDTH)'(COMMAND_ALMFULL_THRESHOLD));
                end
            end

            // synthesis translate_off
            always @(negedge mem_master.clk)
            begin
                // In almost full mode it is illegal for a request to arrive
                // when s0_waitrequest is asserted. If this ever happens it
                // means the almost full protocol has failed and that
                // cmd_space_avail forced back-pressure too late or it was
                // ignored.

                if (~mem_master.reset && cmd_waitrequest && mem_master.write)
                begin
                    $fatal("** ERROR ** %m: instance %0d dropped write transaction",
                           mem_master.instance_number);
                end

                if (~mem_master.reset && cmd_waitrequest && mem_master.read)
                begin
                    $fatal("** ERROR ** %m: instance %0d dropped read transaction",
                           mem_master.instance_number);
                end
            end
            // synthesis translate_on
        end
    endgenerate

    // Debugging signal
    assign mem_master.instance_number = mem_slave.instance_number;

endmodule // ofs_plat_avalon_mem_if_async_shim
