// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "platform_if.vh"

// Only defined in compatibility mode for OPAE SDK's Platform Interface Manager
`ifndef AFU_TOP_REQUIRES_OFS_PLAT_IF_AFU
// and when local memory exists.
`ifdef PLATFORM_PROVIDES_LOCAL_MEMORY

//
// The old avalon_mem_if is very similar to ofs_plat_local_mem_avalon_if,
// though clk and reset are defined differently.
//

// Global log file handle
int avalon_mem_if_log_fd = -1;

interface avalon_mem_if
  #(
    parameter ENABLE_LOG = 0,        // Log events for this instance?
    parameter LOG_NAME = "avalon_mem_if.tsv",

    // Legacy entry -- remains only for compatibility.  The bank number was
    // recorded for debugging but the parameter is difficult to set in a
    // vector of interfaces.  Use bank_number signal below instead.
    parameter BANK_NUMBER = -1,
    // Controls the size of bank_number
    parameter NUM_BANKS = 1,

    parameter ADDR_WIDTH = local_mem_cfg_pkg::LOCAL_MEM_ADDR_WIDTH,
    parameter DATA_WIDTH = local_mem_cfg_pkg::LOCAL_MEM_FULL_BUS_WIDTH,
    parameter BURST_CNT_WIDTH = local_mem_cfg_pkg::LOCAL_MEM_BURST_CNT_WIDTH
    )
   (
    input  wire clk,
    input  wire reset
    );

    // A hack to work around compilers complaining of circular dependence
    // incorrectly when trying to make a new ofs_plat_local_mem_if from an
    // existing one's parameters.
    localparam NUM_BANKS_ = $bits(logic [NUM_BANKS:0]) - 1;
    localparam ADDR_WIDTH_ = $bits(logic [ADDR_WIDTH:0]) - 1;
    localparam DATA_WIDTH_ = $bits(logic [DATA_WIDTH:0]) - 1;
    localparam BURST_CNT_WIDTH_ = $bits(logic [BURST_CNT_WIDTH:0]) - 1;

    // Number of bytes in a data line
    localparam DATA_N_BYTES = (DATA_WIDTH + 7) / 8;

    // Signals
    logic                       waitrequest;
    logic [DATA_WIDTH-1:0]      readdata;
    logic                       readdatavalid;

    logic [ADDR_WIDTH-1:0]      address;
    logic                       write;
    logic                       read;
    logic [BURST_CNT_WIDTH-1:0] burstcount;
    logic [DATA_WIDTH-1:0]      writedata;
    logic [DATA_N_BYTES-1:0]    byteenable;

    // Debugging state.  This will typically be driven to a constant by the
    // code that instantiates the interface object.
    logic [$clog2(NUM_BANKS)-1:0] bank_number;


    //
    // Connection from a module toward the platform (FPGA Interface Manager)
    //
    modport to_fiu
       (
        input  clk,
        input  reset,

        input  waitrequest,
        input  readdata,
        input  readdatavalid,

        output address,
        output write,
        output read,
        output burstcount,
        output writedata,
        output byteenable,

        output bank_number
        );


    //
    // Connection from a module toward the AFU
    //
    modport to_afu
       (
        input  clk,
        input  reset,

        output waitrequest,
        output readdata,
        output readdatavalid,

        input  address,
        input  write,
        input  read,
        input  burstcount,
        input  writedata,
        input  byteenable,

        output bank_number
        );


    //
    // Monitoring port -- all signals are input
    //
    modport monitor
       (
        input  clk,
        input  reset,

        input  waitrequest,
        input  readdata,
        input  readdatavalid,

        input  burstcount,
        input  writedata,
        input  address,
        input  write,
        input  read,
        input  byteenable,

        output bank_number
        );


    //
    //   Debugging
    //

    // synthesis translate_off
    initial
    begin : logger_proc
        if (avalon_mem_if_log_fd == -1)
        begin
            avalon_mem_if_log_fd = $fopen(LOG_NAME, "w");
        end

        // Watch traffic
        if (ENABLE_LOG != 0)
        begin
            forever @(posedge clk)
            begin
                // Read request
                if (! reset && read && ! waitrequest)
                begin
                    $fwrite(avalon_mem_if_log_fd, "%m: %t bank %0d read 0x%x burst 0x%x\n",
                            $time,
                            bank_number,
                            address,
                            burstcount);
                end

                // Read response
                if (! reset && readdatavalid)
                begin
                    $fwrite(avalon_mem_if_log_fd, "%m: %t bank %0d resp 0x%x\n",
                            $time,
                            bank_number,
                            readdata);
                end

                // Write request
                if (! reset && write && ! waitrequest)
                begin
                    $fwrite(avalon_mem_if_log_fd, "%m: %t bank %0d write 0x%x burst 0x%x mask 0x%x data 0x%x\n",
                            $time,
                            bank_number,
                            address,
                            burstcount,
                            byteenable,
                            writedata);
                end
            end
        end
    end
    // synthesis translate_on

endinterface // avalon_mem_if

`endif // `ifdef PLATFORM_PROVIDES_LOCAL_MEMORY
`endif // `ifndef AFU_TOP_REQUIRES_OFS_PLAT_IF_AFU
