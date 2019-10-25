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
// Generic description of an Avalon memory interface.
//

interface ofs_plat_avalon_mem_if
  #(
    // Log events for this instance?
    parameter ofs_plat_log_pkg::t_log_class LOG_CLASS = ofs_plat_log_pkg::NONE,

    parameter ADDR_WIDTH = 0,
    parameter DATA_WIDTH = 0,
    parameter BURST_CNT_WIDTH = 0,

    // This parameter does not affect the interface. Instead, it is a guide to
    // the master indicating the waitrequestAllowance behavior offered by
    // the slave. Be careful to consider the registered delay of the waitrequest
    // signal when counting cycles.
    parameter WAIT_REQUEST_ALLOWANCE = 0
    );

    // A hack to work around compilers complaining of circular dependence
    // incorrectly when trying to make a new ofs_plat_local_mem_if from an
    // existing one's parameters.
    localparam ADDR_WIDTH_ = $bits(logic [ADDR_WIDTH:0]) - 1;
    localparam DATA_WIDTH_ = $bits(logic [DATA_WIDTH:0]) - 1;
    localparam BURST_CNT_WIDTH_ = $bits(logic [BURST_CNT_WIDTH:0]) - 1;

    // Number of bytes in a data line
    localparam DATA_N_BYTES = (DATA_WIDTH + 7) / 8;

    wire clk;
    logic reset;

    // Signals
    logic waitrequest;
    logic [DATA_WIDTH-1:0] readdata;
    logic readdatavalid;
    logic [1:0] response;

    logic [ADDR_WIDTH-1:0] address;
    logic write;
    logic read;
    logic [BURST_CNT_WIDTH-1:0] burstcount;
    logic [DATA_WIDTH-1:0]      writedata;
    logic [DATA_N_BYTES-1:0]    byteenable;

    // Debugging state.  This will typically be driven to a constant by the
    // code that instantiates the interface object.
    int unsigned instance_number;

    //
    // Connection from master toward slave
    //
    modport to_slave
       (
        input  clk,
        input  reset,

        input  waitrequest,
        input  readdata,
        input  readdatavalid,
        input  response,

        output address,
        output write,
        output read,
        output burstcount,
        output writedata,
        output byteenable,

        // Debugging
        input  instance_number
        );

    // Same as normal to_slave, but sets clk and reset
    modport to_slave_clk
       (
        output clk,
        output reset,

        input  waitrequest,
        input  readdata,
        input  readdatavalid,
        input  response,

        output address,
        output write,
        output read,
        output burstcount,
        output writedata,
        output byteenable,

        // Debugging
        output instance_number
        );


    //
    // Connection from slave toward master
    //
    modport to_master
       (
        input  clk,
        input  reset,

        output waitrequest,
        output readdata,
        output readdatavalid,
        output response,

        input  address,
        input  write,
        input  read,
        input  burstcount,
        input  writedata,
        input  byteenable,

        // Debugging
        input  instance_number
        );

    // Same as normal to_master, but sets clk and reset
    modport to_master_clk
       (
        output clk,
        output reset,

        output waitrequest,
        output readdata,
        output readdatavalid,
        output response,

        input  address,
        input  write,
        input  read,
        input  burstcount,
        input  writedata,
        input  byteenable,

        // Debugging
        output instance_number
        );


    //
    // Debugging
    //

    // synthesis translate_off

    // Are all the parameters defined?
    initial
    begin
        if (ADDR_WIDTH == 0)
            $fatal(2, "** ERROR ** %m: ADDR_WIDTH is undefined!");
        if (DATA_WIDTH == 0)
            $fatal(2, "** ERROR ** %m: DATA_WIDTH is undefined!");
        if (BURST_CNT_WIDTH == 0)
            $fatal(2, "** ERROR ** %m: BURST_CNT_WIDTH is undefined!");
    end

    logic [BURST_CNT_WIDTH-1:0] wr_bursts_rem;
    logic wr_sop;
    assign wr_sop = (wr_bursts_rem == 0);

    // Track burst count
    always_ff @(posedge clk)
    begin
        if (write && ! waitrequest)
        begin
            // Track write bursts in order to print "sop"
            if (wr_bursts_rem == 0)
            begin
                wr_bursts_rem <= burstcount - 1;
            end
            else
            begin
                wr_bursts_rem <= wr_bursts_rem - 1;
            end
        end

        if (reset)
        begin
            wr_bursts_rem <= 0;
        end
    end

    // Validate signals
    always_ff @(negedge clk)
    begin
        if (! reset && read && write)
        begin
            $fatal(2, "** ERROR ** %m: Both read and write are asserted!");
        end

        if (! reset && read)
        begin
            if (^address === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: address undefined during a read, currently 0x%x", address);
            end

            if (^burstcount === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: burstcount undefined during a read, currently 0x%x", burstcount);
            end
        end

        // wr_request must be set and may not interrupt a burst
        if (! reset && write)
        begin
            if (wr_sop && (^address === 1'bx))
            begin
                $fatal(2, "** ERROR ** %m: address undefined during a write SOP, currently 0x%x", address);
            end

            if (wr_sop && (^burstcount === 1'bx))
            begin
                $fatal(2, "** ERROR ** %m: wr_burstcount undefined during a write SOP, currently 0x%x", burstcount);
            end
        end
    end

    initial
    begin : logger_proc
        // Watch traffic
        if (LOG_CLASS != ofs_plat_log_pkg::NONE)
        begin
            static int log_fd = ofs_plat_log_pkg::get_fd(LOG_CLASS);

            forever @(posedge clk)
            begin
                // Read request
                if (! reset && read && ! waitrequest)
                begin
                    $fwrite(log_fd, "%m: %t %s %0d read 0x%x burst 0x%x mask 0x%x\n",
                            $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            address,
                            burstcount,
                            byteenable);
                end

                // Read response
                if (! reset && readdatavalid)
                begin
                    $fwrite(log_fd, "%m: %t %s %0d read resp 0x%x (%d)\n",
                            $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            readdata,
                            response);
                end

                // Write request
                if (! reset && write && ! waitrequest)
                begin
                    $fwrite(log_fd, "%m: %t %s %0d write 0x%x %sburst 0x%x mask 0x%x data 0x%x\n",
                            $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            address,
                            ((wr_bursts_rem == 0) ? "sop " : ""),
                            burstcount,
                            byteenable,
                            writedata);
                end
            end
        end
    end
    // synthesis translate_on

endinterface // ofs_plat_avalon_mem_if
