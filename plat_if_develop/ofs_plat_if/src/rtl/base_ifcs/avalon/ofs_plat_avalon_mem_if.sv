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
    parameter BURST_CNT_WIDTH = 7,

    // How many data bits does a bytemask bit cover?
    parameter MASKED_SYMBOL_WIDTH = 8,

    parameter RESPONSE_WIDTH = 2,

    // Extension - Optional user-defined payload.
    // This defines the width of user, readresponseuser and writeresponseuser.
    //
    // The Avalon version of user fields has similar semantics to the AXI
    // user fields. It is returned with responses and some fields have
    // sink-specific meanings. E.g., write fence can be encoded as a user
    // bit on write requests.
    //
    // Unlike AXI, most OFS Avalon sinks do not return user request fields
    // along with responses.
    parameter USER_WIDTH = 8,

    // This parameter does not affect the interface. Instead, it is a guide to
    // the source indicating the waitrequestAllowance behavior offered by
    // the sink. Be careful to consider the registered delay of the waitrequest
    // signal when counting cycles.
    parameter WAIT_REQUEST_ALLOWANCE = 0
    );

    // A hack to work around compilers complaining of circular dependence
    // incorrectly when trying to make a new ofs_plat_local_mem_if from an
    // existing one's parameters.
    localparam ADDR_WIDTH_ = $bits(logic [ADDR_WIDTH:0]) - 1;
    localparam DATA_WIDTH_ = $bits(logic [DATA_WIDTH:0]) - 1;
    localparam BURST_CNT_WIDTH_ = $bits(logic [BURST_CNT_WIDTH:0]) - 1;
    localparam MASKED_SYMBOL_WIDTH_ = $bits(logic [MASKED_SYMBOL_WIDTH:0]) - 1;
    localparam RESPONSE_WIDTH_ = $bits(logic [RESPONSE_WIDTH:0]) - 1;
    localparam USER_WIDTH_ = $bits(logic [USER_WIDTH:0]) - 1;

    // Number of bytes in a data line.
    localparam DATA_N_BYTES = (DATA_WIDTH + 7) / MASKED_SYMBOL_WIDTH;

    wire clk;
    logic reset_n;

    // Signals
    logic waitrequest;

    logic readdatavalid;
    logic [DATA_WIDTH-1:0] readdata;
    logic [RESPONSE_WIDTH-1:0] response;
    // Extension - see USER_WIDTH parameter
    logic [USER_WIDTH-1:0] readresponseuser;

    // Many sinks will not implement write responses. Responses are typically
    // needed only when the commit points of writes relative to other events may
    // vary. Local memory, for example, typically does not implement them.
    // In this interface, read and write responses are completely separate
    // and both may be valid in the same cycle. The writeresponse field
    // holds the write response payload. This separation is necessary since
    // write responses from sinks are optional, making it impossible to
    // calculate reserved space required in clock crossing FIFOs, etc.
    logic writeresponsevalid;
    logic [RESPONSE_WIDTH-1:0] writeresponse;
    // Extension - see USER_WIDTH parameter
    logic [USER_WIDTH-1:0] writeresponseuser;

    logic [ADDR_WIDTH-1:0] address;
    logic write;
    logic read;
    logic [BURST_CNT_WIDTH-1:0] burstcount;
    logic [DATA_WIDTH-1:0]      writedata;
    logic [DATA_N_BYTES-1:0]    byteenable;
    // Extension - see USER_WIDTH parameter
    logic [USER_WIDTH-1:0] user;

    // Debugging state.  This will typically be driven to a constant by the
    // code that instantiates the interface object.
    int unsigned instance_number;

    //
    // Connection from source toward sink
    //
    modport to_sink
       (
        input  clk,
        input  reset_n,

        input  waitrequest,
        input  readdatavalid,
        input  readdata,
        input  response,
        input  readresponseuser,
        input  writeresponsevalid,
        input  writeresponse,
        input  writeresponseuser,

        output address,
        output write,
        output read,
        output burstcount,
        output writedata,
        output byteenable,
        output user,

        // Debugging
        input  instance_number
        );

    // Same as normal to_sink, but sets clk and reset_n
    modport to_sink_clk
       (
        output clk,
        output reset_n,

        input  waitrequest,
        input  readdatavalid,
        input  readdata,
        input  response,
        input  readresponseuser,
        input  writeresponsevalid,
        input  writeresponse,
        input  writeresponseuser,

        output address,
        output write,
        output read,
        output burstcount,
        output writedata,
        output byteenable,
        output user,

        // Debugging
        output instance_number
        );

    // Old naming, maintained for compatibility
    modport to_slave
       (
        input  clk,
        input  reset_n,

        input  waitrequest,
        input  readdatavalid,
        input  readdata,
        input  response,
        input  readresponseuser,
        input  writeresponsevalid,
        input  writeresponse,
        input  writeresponseuser,

        output address,
        output write,
        output read,
        output burstcount,
        output writedata,
        output byteenable,
        output user,

        // Debugging
        input  instance_number
        );


    //
    // Connection from sink toward source
    //
    modport to_source
       (
        input  clk,
        input  reset_n,

        output waitrequest,
        output readdatavalid,
        output readdata,
        output response,
        output readresponseuser,
        output writeresponsevalid,
        output writeresponse,
        output writeresponseuser,

        input  address,
        input  write,
        input  read,
        input  burstcount,
        input  writedata,
        input  byteenable,
        input  user,

        // Debugging
        input  instance_number
        );

    // Same as normal to_source, but sets clk and reset_n
    modport to_source_clk
       (
        output clk,
        output reset_n,

        output waitrequest,
        output readdatavalid,
        output readdata,
        output response,
        output readresponseuser,
        output writeresponsevalid,
        output writeresponse,
        output writeresponseuser,

        input  address,
        input  write,
        input  read,
        input  burstcount,
        input  writedata,
        input  byteenable,
        input  user,

        // Debugging
        output instance_number
        );

    // Old naming, maintained for compatibility
    modport to_master
       (
        input  clk,
        input  reset_n,

        output waitrequest,
        output readdatavalid,
        output readdata,
        output response,
        output readresponseuser,
        output writeresponsevalid,
        output writeresponse,
        output writeresponseuser,

        input  address,
        input  write,
        input  read,
        input  burstcount,
        input  writedata,
        input  byteenable,
        input  user,

        // Debugging
        input  instance_number
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
        if (write && (!waitrequest || (WAIT_REQUEST_ALLOWANCE != 0)))
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

        if (!reset_n)
        begin
            wr_bursts_rem <= 0;
        end
    end

    // Validate signals
    always_ff @(negedge clk)
    begin
        if (reset_n && !waitrequest)
        begin
            if (read && write)
            begin
                $fatal(2, "** ERROR ** %m: Both read and write are asserted!");
            end

            if (read === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: read is uninitialized!");
            end
            if (write === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: write is uninitialized!");
            end

            if (read)
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

            if (write)
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
    end

    initial
    begin
        static string ctx_name = $sformatf("%m");

        // Watch traffic
        if (LOG_CLASS != ofs_plat_log_pkg::NONE)
        begin
            static int log_fd = ofs_plat_log_pkg::get_fd(LOG_CLASS);

            forever @(posedge clk)
            begin
                // Read request
                if (reset_n && read && (!waitrequest || (WAIT_REQUEST_ALLOWANCE != 0)))
                begin
                    $fwrite(log_fd, "%s: %t %s %0d read 0x%x burst 0x%x user 0x%x mask 0x%x\n",
                            ctx_name, $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            address,
                            burstcount,
                            user,
                            byteenable);
                    $fflush(log_fd);
                end

                // Read response
                if (reset_n && readdatavalid)
                begin
                    $fwrite(log_fd, "%s: %t %s %0d read resp 0x%x user 0x%x (0x%x)\n",
                            ctx_name, $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            readdata,
                            readresponseuser,
                            response);
                    $fflush(log_fd);
                end

                // Write request
                if (reset_n && write && (!waitrequest || (WAIT_REQUEST_ALLOWANCE != 0)))
                begin
                    $fwrite(log_fd, "%s: %t %s %0d write 0x%x %sburst 0x%x user 0x%x mask 0x%x data 0x%x\n",
                            ctx_name, $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            address,
                            ((wr_bursts_rem == 0) ? "sop " : ""),
                            burstcount,
                            user,
                            byteenable,
                            writedata);
                    $fflush(log_fd);
                end

                // Write response
                if (reset_n && writeresponsevalid)
                begin
                    $fwrite(log_fd, "%s: %t %s %0d write resp user 0x%x (0x%x)\n",
                            ctx_name, $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            writeresponseuser,
                            writeresponse);
                    $fflush(log_fd);
                end
            end
        end
    end
    // synthesis translate_on

endinterface // ofs_plat_avalon_mem_if
