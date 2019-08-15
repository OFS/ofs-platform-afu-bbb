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

    // Controls the size of instance_number
    parameter NUM_INSTANCES = 1,

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
    localparam NUM_INSTANCES_ = $bits(logic [NUM_INSTANCES:0]) - 1;
    localparam ADDR_WIDTH_ = $bits(logic [ADDR_WIDTH:0]) - 1;
    localparam DATA_WIDTH_ = $bits(logic [DATA_WIDTH:0]) - 1;
    localparam BURST_CNT_WIDTH_ = $bits(logic [BURST_CNT_WIDTH:0]) - 1;

    // Number of bytes in a data line
    localparam DATA_N_BYTES = (DATA_WIDTH + 7) / 8;

    logic clk;
    logic reset;

    // Signals
    logic waitrequest;
    logic [DATA_WIDTH-1:0] readdata;
    logic readdatavalid;
    logic writeresponsevalid;
    logic [1:0] response;

    logic [ADDR_WIDTH-1:0] address;
    logic write;
    logic read;
    logic [BURST_CNT_WIDTH-1:0] burstcount;
    logic [DATA_WIDTH-1:0]      writedata;
    logic [DATA_N_BYTES-1:0]    byteenable;

    // Debugging state.  This will typically be driven to a constant by the
    // code that instantiates the interface object.
    logic [$clog2(NUM_INSTANCES)-1:0] instance_number;

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
        input  writeresponsevalid,
        input  response,

        output address,
        output write,
        output read,
        output burstcount,
        output writedata,
        output byteenable,

        output instance_number
        );


    //
    // Connection from slave toward master
    //
    modport to_master
       (
        output clk,
        output reset,

        output waitrequest,
        output readdata,
        output readdatavalid,
        output writeresponsevalid,
        output response,

        input  address,
        input  write,
        input  read,
        input  burstcount,
        input  writedata,
        input  byteenable,

        output instance_number
        );


    //
    // Debugging
    //

    // synthesis translate_off
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
                    $fwrite(log_fd, "%m: %t %s %0d read 0x%x burst 0x%x\n",
                            $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            address,
                            burstcount);
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
                    $fwrite(log_fd, "%m: %t %s %0d write 0x%x burst 0x%x mask 0x%x data 0x%x\n",
                            $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            address,
                            burstcount,
                            byteenable,
                            writedata);
                end

                // Write response
                if (! reset && writeresponsevalid)
                begin
                    $fwrite(log_fd, "%m: %t %s %0d write resp (%d)\n",
                            $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            response);
                end
            end
        end
    end
    // synthesis translate_on

endinterface // ofs_plat_avalon_mem_if
