// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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

    // Size of the tuser payload
    localparam TUSER_WIDTH = $bits(TUSER_TYPE);

    localparam TKEEP_WIDTH = (TDATA_WIDTH + 7) / 8;
    typedef logic [TKEEP_WIDTH-1 : 0] t_keep;

    wire clk;
    logic reset_n;

    // Data stream
    typedef struct packed {
        logic last;
        t_keep keep;
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
                    $fwrite(log_fd, "%s: %t %s %0d last %0d keep 0x%x user 0x%x data 0x%x\n",
                            ctx_name, $time,
                            ofs_plat_log_pkg::instance_name[LOG_CLASS],
                            instance_number,
                            t.last, t.keep, t.user, t.data);
                end
            end
        end
    end

    // synthesis translate_on

endinterface // ofs_plat_axi_stream_if
