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
// Generic description of an Avalon split bus read and write memory interface.
// The standard Avalon interface shares the address port for reads and writes.
// This description is logically two Avalon buses: one for reads and one for
// writes.
//

interface ofs_plat_avalon_mem_rdwr_if
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


    // Shared
    wire clk;
    logic reset;


    // Read bus
    logic rd_waitrequest;
    logic [DATA_WIDTH-1:0] rd_readdata;
    logic rd_readdatavalid;
    logic [1:0] rd_response;

    logic [ADDR_WIDTH-1:0] rd_address;
    logic rd_read;
    logic [BURST_CNT_WIDTH-1:0] rd_burstcount;
    logic [DATA_N_BYTES-1:0] rd_byteenable;
    // rd_request is non-standard. It is currently reserved and should be set to
    // zero. See wr_request for a more detailed explanation.
    logic rd_request;


    // Write bus
    logic wr_waitrequest;
    logic wr_writeresponsevalid;
    logic [1:0] wr_response;

    logic [ADDR_WIDTH-1:0] wr_address;
    logic wr_write;
    logic [BURST_CNT_WIDTH-1:0] wr_burstcount;
    logic [DATA_WIDTH-1:0] wr_writedata;
    logic [DATA_N_BYTES-1:0] wr_byteenable;
    // wr_request is non-standard. When used as a host channel to host memory, the
    // Avalon ordered bus does not map well to either AXI or CCI-P, which allow
    // out-of-order completion. On some platforms, the semantics of Avalon ordering
    // may be redefined to permit stores to be reordered in the FIU. (Despite this,
    // writeresponsevalid always returns in request order so that responses can be
    // matched with requests.) Setting the wr_request flag indicates a command to
    // the FIU. Currently, the only command is a write fence. When wr_request is
    // set the wr_address field must be all zeros. Non-zero addresses are reserved
    // for future use.
    //
    // The simplest way to pass rd_request or wr_request through standard Avalon
    // networks that lack the port is by widening the address field by one bit and
    // sending request in parallel through the address port.
    logic wr_request;


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

        // Read bus
        input  rd_waitrequest,
        input  rd_readdata,
        input  rd_readdatavalid,
        input  rd_response,

        output rd_address,
        output rd_read,
        output rd_burstcount,
        output rd_byteenable,
        output rd_request,

        // Write bus
        input  wr_waitrequest,
        input  wr_writeresponsevalid,
        input  wr_response,

        output wr_address,
        output wr_write,
        output wr_burstcount,
        output wr_writedata,
        output wr_byteenable,
        output wr_request,

        // Debugging
        input instance_number
        );

    // Same as normal to_slave, but sets clk and reset
    modport to_slave_clk
       (
        output clk,
        output reset,

        // Read bus
        input  rd_waitrequest,
        input  rd_readdata,
        input  rd_readdatavalid,
        input  rd_response,

        output rd_address,
        output rd_read,
        output rd_burstcount,
        output rd_byteenable,
        output rd_request,

        // Write bus
        input  wr_waitrequest,
        input  wr_writeresponsevalid,
        input  wr_response,

        output wr_address,
        output wr_write,
        output wr_burstcount,
        output wr_writedata,
        output wr_byteenable,
        output wr_request,

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

        // Read bus
        output rd_waitrequest,
        output rd_readdata,
        output rd_readdatavalid,
        output rd_response,

        input  rd_address,
        input  rd_read,
        input  rd_burstcount,
        input  rd_byteenable,
        input  rd_request,

        // Write bus
        output wr_waitrequest,
        output wr_writeresponsevalid,
        output wr_response,

        input  wr_address,
        input  wr_write,
        input  wr_burstcount,
        input  wr_writedata,
        input  wr_byteenable,
        input  wr_request,

        // Debugging
        input  instance_number
        );

    // Same as normal to_master, but sets clk and reset
    modport to_master_clk
       (
        output clk,
        output reset,

        // Read bus
        output rd_waitrequest,
        output rd_readdata,
        output rd_readdatavalid,
        output rd_response,

        input  rd_address,
        input  rd_read,
        input  rd_burstcount,
        input  rd_byteenable,
        input  rd_request,

        // Write bus
        output wr_waitrequest,
        output wr_writeresponsevalid,
        output wr_response,

        input  wr_address,
        input  wr_write,
        input  wr_burstcount,
        input  wr_writedata,
        input  wr_byteenable,
        input  wr_request,

        // Debugging
        output instance_number
        );


    //
    // Debugging and error checking
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
        if (wr_write && ! wr_waitrequest)
        begin
            // Track write bursts in order to print "sop"
            if (wr_bursts_rem == 0)
            begin
                wr_bursts_rem <= wr_burstcount - 1;
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
        if (! reset && rd_read)
        begin
            if (^rd_address === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: rd_address undefined during a read, currently 0x%x", rd_address);
            end

            if (^rd_burstcount === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: rd_burstcount undefined during a read, currently 0x%x", rd_burstcount);
            end

            // rd_request must always be 0
            if (rd_request !== 1'b0)
            begin
                $fatal(2, "** ERROR ** %m: rd_request must be 0, currently %0d", rd_request);
            end
        end

        // wr_request must be set and may not interrupt a burst
        if (! reset && wr_write)
        begin
            if (wr_sop && (^wr_address === 1'bx))
            begin
                $fatal(2, "** ERROR ** %m: wr_address undefined during a write SOP, currently 0x%x", wr_address);
            end

            if (wr_sop && (^wr_burstcount === 1'bx))
            begin
                $fatal(2, "** ERROR ** %m: wr_burstcount undefined during a write SOP, currently 0x%x", wr_burstcount);
            end

            if (wr_request === 'x)
            begin
                $fatal(2, "** ERROR ** %m: wr_request is uninitialized during a write");
            end

            if (wr_request == 1'b1)
            begin
                if (! wr_sop)
                begin
                    $fatal(2, "** ERROR ** %m: wr_request may not be set in the middle of a burst");
                end

                if (wr_address != 0)
                begin
                    $fatal(2, "** ERROR ** %m: wr_address (0x%x) must be 0 when wr_request is set", wr_address);
                end

                if (wr_burstcount != 1)
                begin
                    $fatal(2, "** ERROR ** %m: wr_burstcount (0x%x) must be 1 when wr_request is set", wr_burstcount);
                end
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
                if (! reset && rd_read && ! rd_waitrequest)
                begin
                    $fwrite(log_fd, "%m: %t %s %0d read 0x%x burst 0x%x\ mask 0x%x\n",
                            $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            rd_address,
                            rd_burstcount,
                            rd_byteenable);
                end

                // Read response
                if (! reset && rd_readdatavalid)
                begin
                    $fwrite(log_fd, "%m: %t %s %0d read resp 0x%x (%d)\n",
                            $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            rd_readdata,
                            rd_response);
                end

                // Write request
                if (! reset && wr_write && ! wr_waitrequest)
                begin
                    $fwrite(log_fd, "%m: %t %s %0d write %s0x%x %sburst 0x%x mask 0x%x data 0x%x\n",
                            $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            ((wr_request == 1'b0) ? "" : "fence "),
                            wr_address,
                            (wr_sop ? "sop " : ""),
                            wr_burstcount,
                            wr_byteenable,
                            wr_writedata);
                end

                if (! reset && wr_writeresponsevalid)
                begin
                    $fwrite(log_fd, "%m: %t %s %0d write resp (%d)\n",
                            $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            wr_response);
                end
            end
        end
    end
    // synthesis translate_on

endinterface // ofs_plat_avalon_mem_rdwr_if
