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
// Generic description of an AXI-Lite interface. The signals are compatible
// with AXI5-Lite, which extends AXI4-Lite with support for arbitrary width
// data (up to 1024 bits) and out-of-order source responses (using rid/wid).
//
// AXI-Lite does not supports bursts. All requests are a single beat.
//
//
// Buses are organized as structs. The full AXI name is the contatenation
// of the struct instance and the field, e.g. aw.addr. The struct-based
// organization is chosen for a number of reasons, primarily:
//
//  - To simplify port declaration and assignment.
//
//  - To add a mechanism for adding new fields while maintaining compatibility
//    with existing logic. For maximum portability when writing to a bus,
//    code should first assign '0 to an entire struct and then set values
//    of individual fields. E.g.:
//        always_comb
//        begin
//           bus.aw = '0;
//           bus.aw.addr = addr;
//           ...
//           bus.awvalid = 1'b1;
//        end
//

interface ofs_plat_axi_mem_lite_if
  #(
    // Log events for this instance?
    parameter ofs_plat_log_pkg::t_log_class LOG_CLASS = ofs_plat_log_pkg::NONE,

    parameter ADDR_WIDTH = 0,
    parameter DATA_WIDTH = 0,
    parameter RID_WIDTH = 1,
    parameter WID_WIDTH = 1,
    parameter USER_WIDTH = 1,

    // Disable simulation time checks? Normally this should be left enabled.
    parameter DISABLE_CHECKER = 0
    );

    import ofs_plat_axi_mem_pkg::*;

    // A hack to work around compilers complaining of circular dependence
    // incorrectly when trying to make a new ofs_plat_axi_mem_lite_if from
    // an existing one's parameters.
    localparam ADDR_WIDTH_ = $bits(logic [ADDR_WIDTH:0]) - 1;
    localparam DATA_WIDTH_ = $bits(logic [DATA_WIDTH:0]) - 1;
    localparam RID_WIDTH_ = $bits(logic [RID_WIDTH:0]) - 1;
    localparam WID_WIDTH_ = $bits(logic [WID_WIDTH:0]) - 1;
    localparam USER_WIDTH_ = $bits(logic [USER_WIDTH:0]) - 1;

    // Number of bytes in a data line
    localparam DATA_N_BYTES = (DATA_WIDTH + 7) / 8;

    typedef logic [ADDR_WIDTH-1 : 0] t_addr;
    typedef logic [DATA_WIDTH-1 : 0] t_data;

    // Mask to enable specific write data bytes
    typedef logic [DATA_N_BYTES-1 : 0] t_byte_mask;

    // Read and write tags
    typedef logic [RID_WIDTH-1 : 0] t_rid;
    typedef logic [WID_WIDTH-1 : 0] t_wid;

    // User data width. We use the same size for user data everywhere
    // because the sink, by OFS convention, returns the user data passed
    // to the address channel with a response. User data passed with write
    // data is not returned to the source.
    typedef logic [USER_WIDTH-1 : 0] t_user;

    // Shared
    wire clk;
    logic reset_n;

    // Write address channel
    typedef struct packed {
        t_wid id;
        t_addr addr;
        t_axi_log2_beat_size size;
        t_axi_prot prot;
        t_user user;
    } t_axi_mem_lite_aw;
    localparam T_AW_WIDTH = $bits(t_axi_mem_lite_aw);

    t_axi_mem_lite_aw aw;
    logic awvalid;
    logic awready;

    // Write data channel
    typedef struct packed {
        t_data data;
        t_byte_mask strb;
        t_user user;
    } t_axi_mem_lite_w;
    localparam T_W_WIDTH = $bits(t_axi_mem_lite_w);

    t_axi_mem_lite_w w;
    logic wvalid;
    logic wready;

    // Write response channel
    typedef struct packed {
        t_wid id;
        t_axi_resp resp;
        t_user user;                    // By convention sinks return aw.user
                                        // in b.user, though sinks may document
                                        // some other behavior.
    } t_axi_mem_lite_b;
    localparam T_B_WIDTH = $bits(t_axi_mem_lite_b);

    t_axi_mem_lite_b b;
    logic bvalid;
    logic bready;

    // Read address channel
    typedef struct packed {
        t_rid id;
        t_addr addr;
        t_axi_log2_beat_size size;
        t_axi_prot prot;
        t_user user;
    } t_axi_mem_lite_ar;
    localparam T_AR_WIDTH = $bits(t_axi_mem_lite_ar);

    t_axi_mem_lite_ar ar;
    logic arvalid;
    logic arready;

    // Read response data channel
    typedef struct packed {
        t_rid id;
        t_data data;
        t_axi_resp resp;
        t_user user;                    // By convention sinks return ar.user
                                        // in r.user, though sinks may document
                                        // some other behavior.
    } t_axi_mem_lite_r;
    localparam T_R_WIDTH = $bits(t_axi_mem_lite_r);

    t_axi_mem_lite_r r;
    logic rvalid;
    logic rready;

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

        // Write address channel
        output aw, awvalid,
        input  awready,

        // Write data channel
        output w, wvalid,
        input  wready,

        // Write response channel
        input  b, bvalid,
        output bready,

        // Read address channel
        output ar, arvalid,
        input  arready,

        // Read response data channel
        input  r, rvalid,
        output rready,

        // Debugging
        input  instance_number
        );

    // Same as normal to_sink, but sets clk and reset_n
    modport to_sink_clk
       (
        output clk,
        output reset_n,

        // Write address channel
        output aw, awvalid,
        input  awready,

        // Write data channel
        output w, wvalid,
        input  wready,

        // Write response channel
        input  b, bvalid,
        output bready,

        // Read address channel
        output ar, arvalid,
        input  arready,

        // Read response data channel
        input  r, rvalid,
        output rready,

        // Debugging
        output instance_number
        );

    // Old naming, maintained for compatibility
    modport to_slave
       (
        input  clk,
        input  reset_n,

        // Write address channel
        output aw, awvalid,
        input  awready,

        // Write data channel
        output w, wvalid,
        input  wready,

        // Write response channel
        input  b, bvalid,
        output bready,

        // Read address channel
        output ar, arvalid,
        input  arready,

        // Read response data channel
        input  r, rvalid,
        output rready,

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

        // Write address channel
        input  aw, awvalid,
        output awready,

        // Write data channel
        input  w, wvalid,
        output wready,

        // Write response channel
        output b, bvalid,
        input  bready,

        // Read address channel
        input  ar, arvalid,
        output arready,

        // Read response data channel
        output r, rvalid,
        input  rready,

        // Debugging
        input  instance_number
        );

    // Same as normal to_source, but sets clk and reset_n
    modport to_source_clk
       (
        output clk,
        output reset_n,

        // Write address channel
        input  aw, awvalid,
        output awready,

        // Write data channel
        input  w, wvalid,
        output wready,

        // Write response channel
        output b, bvalid,
        input  bready,

        // Read address channel
        input  ar, arvalid,
        output arready,

        // Read response data channel
        output r, rvalid,
        input  rready,

        // Debugging
        output instance_number
        );

    // Old naming, maintained for compatibility
    modport to_master
       (
        input  clk,
        input  reset_n,

        // Write address channel
        input  aw, awvalid,
        output awready,

        // Write data channel
        input  w, wvalid,
        output wready,

        // Write response channel
        output b, bvalid,
        input  bready,

        // Read address channel
        input  ar, arvalid,
        output arready,

        // Read response data channel
        output r, rvalid,
        input  rready,

        // Debugging
        input  instance_number
        );


    //
    // Debugging and error checking
    //

    `include "ofs_plat_axi_mem_checker.vh"

    // synthesis translate_off

    // Are all the parameters defined?
    initial
    begin
        if (ADDR_WIDTH == 0)
            $fatal(2, "** ERROR ** %m: ADDR_WIDTH is undefined!");
        if (DATA_WIDTH == 0)
            $fatal(2, "** ERROR ** %m: DATA_WIDTH is undefined!");
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
                // Write address
                if (reset_n && awvalid && awready)
                begin
                    $fwrite(log_fd, "%s: %t %s %0d AW addr 0x%x size 0x%x id 0x%x prot 0x%x user 0x%x\n",
                            ctx_name, $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            aw.addr, aw.size, aw.id, aw.prot, aw.user);
                end

                // Write data
                if (reset_n && wvalid && wready)
                begin
                    $fwrite(log_fd, "%s: %t %s %0d W  data 0x%x strb 0x%x user 0x%x\n",
                            ctx_name, $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            w.data, w.strb, w.user);
                end

                // Write response
                if (reset_n && bvalid && bready)
                begin
                    $fwrite(log_fd, "%s: %t %s %0d B  resp 0x%x id 0x%x user 0x%x\n",
                            ctx_name, $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            b.resp, b.id, b.user);
                end

                // Read address
                if (reset_n && arvalid && arready)
                begin
                    $fwrite(log_fd, "%s: %t %s %0d AR addr 0x%x size 0x%x id 0x%x prot 0x%x user 0x%x\n",
                            ctx_name, $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            ar.addr, ar.size, ar.id, ar.prot, ar.user);
                end

                // Read data
                if (reset_n && rvalid && rready)
                begin
                    $fwrite(log_fd, "%s: %t %s %0d R  resp 0x%x id 0x%x data 0x%x user 0x%x\n",
                            ctx_name, $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            r.resp, r.id, r.data, r.user);
                end
            end
        end
    end

    // synthesis translate_on

endinterface // ofs_plat_axi_mem_lite_if
