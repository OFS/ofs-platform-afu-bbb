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
    parameter COMMAND_FIFO_DEPTH = 128,
    // When non-zero, set the command buffer such that COMMAND_ALMFULL_THRESHOLD
    // requests can be received after mem_master.waitrequest is asserted.
    parameter COMMAND_ALMFULL_THRESHOLD = 0
    )
   (
    ofs_plat_avalon_mem_rdwr_if.to_slave mem_slave,
    ofs_plat_avalon_mem_rdwr_if.to_master mem_master
    );

    localparam SPACE_AVAIL_WIDTH = $clog2(COMMAND_FIFO_DEPTH) + 1;

    logic cmd_rd_waitrequest, cmd_wr_waitrequest;
    logic [SPACE_AVAIL_WIDTH-1:0] cmd_rd_space_avail, cmd_wr_space_avail;

    typedef logic [1:0] t_response;
    t_response m0_response_dummy;

    //
    // Read bus clock crossing
    //
    ofs_plat_utils_avalon_mm_clock_crossing_bridge
      #(
        // Leave room for passing "response" along with readdata
        .DATA_WIDTH($bits(t_response) + mem_slave.DATA_WIDTH),
        .HDL_ADDR_WIDTH(1 + mem_slave.ADDR_WIDTH),
        .BURSTCOUNT_WIDTH(mem_slave.BURST_CNT_WIDTH),
        .COMMAND_FIFO_DEPTH(COMMAND_FIFO_DEPTH),
        .RESPONSE_FIFO_DEPTH(2 ** (mem_slave.BURST_CNT_WIDTH + 1))
        )
      avmm_cross_rd
       (
        .s0_clk(mem_master.clk),
        .s0_reset(mem_master.reset),

        .m0_clk(mem_slave.clk),
        .m0_reset(mem_slave.reset),

        .s0_waitrequest(cmd_rd_waitrequest),
        .s0_readdata({mem_master.rd_response, mem_master.rd_readdata}),
        .s0_readdatavalid(mem_master.rd_readdatavalid),
        .s0_burstcount(mem_master.rd_burstcount),
        .s0_writedata('0),
        .s0_address({mem_master.rd_request, mem_master.rd_address}),
        .s0_write(1'b0),
        .s0_read(mem_master.rd_read),
        .s0_byteenable(mem_master.rd_byteenable),
        .s0_debugaccess(1'b0),
        .s0_space_avail_data(cmd_rd_space_avail),

        .m0_waitrequest(mem_slave.rd_waitrequest),
        .m0_readdata({mem_slave.rd_response, mem_slave.rd_readdata}),
        .m0_readdatavalid(mem_slave.rd_readdatavalid),
        .m0_burstcount(mem_slave.rd_burstcount),
        .m0_writedata(),
        .m0_address({mem_slave.rd_request, mem_slave.rd_address}),
        .m0_write(),
        .m0_read(mem_slave.rd_read),
        .m0_byteenable(mem_slave.rd_byteenable),
        .m0_debugaccess()
        );

    //
    // Write bus clock crossing
    //
    ofs_plat_utils_avalon_mm_clock_crossing_bridge
      #(
        .DATA_WIDTH(mem_slave.DATA_WIDTH),
        .HDL_ADDR_WIDTH(1 + mem_slave.ADDR_WIDTH),
        .BURSTCOUNT_WIDTH(mem_slave.BURST_CNT_WIDTH),
        .COMMAND_FIFO_DEPTH(COMMAND_FIFO_DEPTH),
        .RESPONSE_FIFO_DEPTH(2 ** (mem_slave.BURST_CNT_WIDTH + 1))
        )
      avmm_cross_wr
       (
        .s0_clk(mem_master.clk),
        .s0_reset(mem_master.reset),

        .m0_clk(mem_slave.clk),
        .m0_reset(mem_slave.reset),

        .s0_waitrequest(cmd_wr_waitrequest),
        .s0_readdata(),
        .s0_readdatavalid(),
        .s0_burstcount(mem_master.wr_burstcount),
        .s0_writedata(mem_master.wr_writedata),
        .s0_address({mem_master.wr_request, mem_master.wr_address}),
        .s0_write(mem_master.wr_write),
        .s0_read(1'b0),
        .s0_byteenable(mem_master.wr_byteenable),
        .s0_debugaccess(1'b0),
        .s0_space_avail_data(cmd_wr_space_avail),

        .m0_waitrequest(mem_slave.wr_waitrequest),
        .m0_readdata('0),
        .m0_readdatavalid(1'b0),
        .m0_burstcount(mem_slave.wr_burstcount),
        .m0_writedata(mem_slave.wr_writedata),
        .m0_address({mem_slave.wr_request, mem_slave.wr_address}),
        .m0_write(mem_slave.wr_write),
        .m0_read(),
        .m0_byteenable(mem_slave.wr_byteenable),
        .m0_debugaccess()
        );

    //
    // The standard Avalon clock crossing bridge doesn't pass write responses.
    // Use a simple dual clock FIFO. Since the data in the FIFO is quite narrow
    // and the number of writes in flight is fixed by controller queues, we
    // don't count available queue slots and assume that the FIFO will never
    // overflow.
    //
    logic wr_response_not_valid;
    logic wr_response_full;

    ofs_plat_utils_dc_fifo
      #(
        .DATA_WIDTH($bits(t_response)),
        .DEPTH_RADIX(12)
        )
      avmm_cross_wr_response
       (
        .aclr(mem_master.reset),
        .data(mem_slave.wr_response),
        .rdclk(mem_master.clk),
        // dcfifo has "underflow_checking" on, so safe to hold rdreq
        .rdreq(1'b1),
        .wrclk(mem_slave.clk),
        .wrreq(mem_slave.wr_writeresponsevalid),
        .q(mem_master.wr_response),
        .rdempty(wr_response_not_valid),
        .rdfull(),
        .rdusedw(),
        .wrempty(),
        .wrfull(wr_response_full),
        .wralmfull(),
        .wrusedw()
        );

    always_ff @(posedge mem_master.clk)
    begin
        mem_master.wr_writeresponsevalid <= ~wr_response_not_valid && ~mem_master.reset;
    end


    // Compute mem_master.waitrequest
    generate
        if (COMMAND_ALMFULL_THRESHOLD == 0)
        begin : no_almfull
            // Use the usual Avalon MM protocol
            assign mem_master.rd_waitrequest = cmd_rd_waitrequest;
            assign mem_master.wr_waitrequest = cmd_wr_waitrequest;
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
                    mem_master.rd_waitrequest <= 1'b1;
                    mem_master.wr_waitrequest <= 1'b1;
                end
                else
                begin
                    mem_master.rd_waitrequest <= cmd_rd_waitrequest ||
                        (cmd_rd_space_avail <= (SPACE_AVAIL_WIDTH)'(COMMAND_ALMFULL_THRESHOLD));
                    mem_master.wr_waitrequest <= cmd_wr_waitrequest ||
                        (cmd_wr_space_avail <= (SPACE_AVAIL_WIDTH)'(COMMAND_ALMFULL_THRESHOLD));
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

                if (~mem_master.reset && cmd_wr_waitrequest && mem_master.wr_write)
                begin
                    $fatal(2, "** ERROR ** %m: instance %0d dropped write transaction",
                           mem_master.instance_number);
                end

                if (~mem_master.reset && cmd_rd_waitrequest && mem_master.rd_read)
                begin
                    $fatal(2, "** ERROR ** %m: instance %0d dropped read transaction",
                           mem_master.instance_number);
                end
            end
            // synthesis translate_on
        end
    endgenerate

endmodule // ofs_plat_avalon_mem_rdwr_if_async_shim
