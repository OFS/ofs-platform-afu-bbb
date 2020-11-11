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

//
// AXI stream interface. The payload and user types, TDATA_TYPE and TUSER_TYPE,
// are parameters to the interface. If the interface is instantiated with a
// struct, the fields can be accessed by name in both sources and sinks.
//

interface ofs_plat_axi_stream_if
  #(
    // Log events for this instance?
    parameter ofs_plat_log_pkg::t_log_class LOG_CLASS = ofs_plat_log_pkg::NONE,

    parameter type TDATA_TYPE,
    parameter type TUSER_TYPE,

    // Disable simulation time checks? Normally this should be left enabled.
    parameter DISABLE_CHECKER = 0
    );

    // Size of the data payload
    localparam TDATA_WIDTH = $bits(TDATA_TYPE);
    // For consistency with ofs_plat_axi_stream_opaque_if
    localparam TDATA_WIDTH_ = $bits(logic [TDATA_WIDTH:0]) - 1;

    // Size of the tuser payload
    localparam TUSER_WIDTH = $bits(TUSER_TYPE);
    localparam TUSER_WIDTH_ = $bits(logic [TUSER_WIDTH:0]) - 1;

    wire clk;
    logic reset_n;

    // Data stream
    typedef struct packed {
        logic last;
        TUSER_TYPE user;
        TDATA_TYPE data;
    } t_payload;
    localparam T_PAYLOAD_WIDTH = $bits(t_payload);

    t_payload t;
    logic tvalid;
    logic tready;

    // Debugging state.  This will typically be driven to a constant by the
    // code that instantiates the interface object.
    int unsigned instance_number;

    //
    // Connection from source toward sink
    //
    modport to_sink
       (
        input  clk, reset_n,

        output tvalid,
        input  tready,

        output t,

        // Debugging
        input  instance_number
        );

    // Same as normal to_sink, but sets clk and reset_n
    modport to_sink_clk
       (
        output clk, reset_n,

        output tvalid,
        input  tready,

        output t,

        // Debugging
        output instance_number
        );

    // Old naming, maintained for compatibility
    modport to_slave
       (
        input  clk, reset_n,

        output tvalid,
        input  tready,

        output t,

        // Debugging
        input  instance_number
        );


    //
    // Connection from sink toward source
    //
    modport to_source
       (
        input  clk, reset_n,

        input  tvalid,
        output tready,

        input  t,

        // Debugging
        input  instance_number
        );

    // Same as normal to_source, but sets clk and reset_n
    modport to_source_clk
       (
        output clk, reset_n,

        input  tvalid,
        output tready,

        input  t,

        // Debugging
        output instance_number
        );

    // Old naming, maintained for compatibility
    modport to_master
       (
        input  clk, reset_n,

        input  tvalid,
        output tready,

        input  t,

        // Debugging
        input  instance_number
        );


    // synthesis translate_off

    // Validate signals
    always_ff @(negedge clk)
    begin
        if (reset_n && (DISABLE_CHECKER == 0))
        begin
            if (tvalid === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: tvalid is uninitialized!");
            end

            if (tready === 1'bx)
            begin
                $fatal(2, "** ERROR ** %m: tready is uninitialized!");
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
                // Write address
                if (reset_n && tvalid && tready)
                begin
                    $fwrite(log_fd, "%s: %t %s %0d last %0d user 0x%x data 0x%x\n",
                            ctx_name, $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            t.last, t.user, t.data);
                end
            end
        end
    end

    // synthesis translate_on

endinterface // ofs_plat_axi_stream_if
