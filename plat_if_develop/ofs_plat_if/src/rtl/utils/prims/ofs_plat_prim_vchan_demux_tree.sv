// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Break an incoming multiplexed stream into separate ports,
// one per virtual channel, potentially using a tree if the
// switched bus is too wide.
//
// The output port index is stored in mux_in.t.user.
//

`include "ofs_plat_if.vh"

module ofs_plat_prim_vchan_demux_tree
  #(
    parameter NUM_DEMUX_PORTS = 2,
    parameter MAX_SWITCHED_DATA_WIDTH = 4096,
    parameter MAX_PORTS_PER_LEVEL = 8
    )
   (
    ofs_plat_axi_stream_if.to_source mux_in,
    ofs_plat_axi_stream_if.to_sink demux_out[NUM_DEMUX_PORTS]
    );

    wire clk = mux_in.clk;
    wire reset_n = mux_in.reset_n;

    localparam M_IN_DATA_WIDTH = mux_in.TDATA_WIDTH;
    localparam PORT_SEL_WIDTH = $clog2(NUM_DEMUX_PORTS);

    // Number of ports that fit in the max switched data width.
    // Minimum 2 to form a tree.
    localparam PORTS_PER_LEVEL_BASE = MAX_SWITCHED_DATA_WIDTH / M_IN_DATA_WIDTH;
    // Ports per level, bounded by 2 and MAX_PORTS_PER_LEVEL.
    localparam PORTS_PER_LEVEL =
        PORTS_PER_LEVEL_BASE <= 2 ? 2 :
            ((PORTS_PER_LEVEL_BASE >= MAX_PORTS_PER_LEVEL) ? MAX_PORTS_PER_LEVEL :
                                                             PORTS_PER_LEVEL_BASE);

    if (NUM_DEMUX_PORTS == 1) begin : direct

        // Only 1 output port! Just wire the input to the output.
        ofs_plat_axi_stream_if_connect
            conn (.stream_source(mux_in), .stream_sink(demux_out[0]));

    end
    else if (NUM_DEMUX_PORTS <= PORTS_PER_LEVEL) begin : demux

        // Fanout is low enough. Generate the target MUX.
        ofs_plat_prim_vchan_demux
          #(
            .NUM_DEMUX_PORTS(NUM_DEMUX_PORTS)
            )
          m
           (
            .mux_in,
            .demux_out
            );

    end
    else begin : tree

        //
        // High fanout case. Add an intermediate node with NUM_TREE_PORTS
        // ports, distributing the full incoming demux set across them.
        // Then recursively instantiate a DEMUX for each cluster.
        //

        // Pick a subset of the port index bits from the user field and apply
        // them to an intermediate tree node here. The tree node will have
        // a number of ports <= PORTS_PER_LEVEL that is a power of 2.
        // QoS is not a factor in port distribution since there is a single
        // source of data.
        localparam int TREE_PORT_IDX_WIDTH_X = $floor($log10(PORTS_PER_LEVEL) / $log10(2));
        localparam TREE_PORT_IDX_WIDTH = 1;

        // High bits of the port index select the intermediate tree node's
        // output port.
        localparam TREE_PORT_IDX_START = PORT_SEL_WIDTH - TREE_PORT_IDX_WIDTH;
        // Lower bits of the port index are passed to demux nodes lower
        // down in the tree.
        localparam DEMUX_OUT_PER_PORT = 1 << TREE_PORT_IDX_START;

        // Spread DEMUX_OUT_PER_PORT across however many ports are needed
        // to map all NUM_DEMUX_PORTS.
        localparam NUM_TREE_PORTS = (NUM_DEMUX_PORTS + DEMUX_OUT_PER_PORT - 1) /
                                    DEMUX_OUT_PER_PORT;

        ofs_plat_axi_stream_if
          #(
            .TDATA_TYPE(logic [mux_in.TDATA_WIDTH-1:0]),
            .TUSER_TYPE(logic [mux_in.TUSER_WIDTH-1:0])
            )
          tree_demux_out[NUM_TREE_PORTS]();


        for (genvar i = 0; i < NUM_TREE_PORTS; i += 1) begin : t
            assign tree_demux_out[i].clk = clk;
            assign tree_demux_out[i].reset_n = reset_n;
            assign tree_demux_out[i].instance_number = mux_in.instance_number;

            // For all but the last instance, map DEMUX_OUT_PER_PORT to
            // tree_demux_out[i]. The last port maps whatever remains.
            localparam ITER_NUM_DEMUX_PORTS =
                (i == NUM_TREE_PORTS - 1) ? (NUM_DEMUX_PORTS - i * DEMUX_OUT_PER_PORT)
                                           : DEMUX_OUT_PER_PORT;

            ofs_plat_prim_vchan_demux_tree
              #(
                .NUM_DEMUX_PORTS(ITER_NUM_DEMUX_PORTS),
                .MAX_SWITCHED_DATA_WIDTH(MAX_SWITCHED_DATA_WIDTH)
                )
              node
               (
                .mux_in(tree_demux_out[i]),
                .demux_out(demux_out[i * DEMUX_OUT_PER_PORT +: ITER_NUM_DEMUX_PORTS])
                );
        end

        // Demultiplex the intermediate tree nodes to output. Higher bits
        // in the port index are used for routing.
        ofs_plat_prim_vchan_demux
          #(
            .NUM_DEMUX_PORTS(NUM_TREE_PORTS),
            .PORT_IDX_START_BIT(TREE_PORT_IDX_START)
            )
          m
           (
            .mux_in,
            .demux_out(tree_demux_out)
            );

    end


    // ====================================================================
    //
    //  Validation
    //
    // ====================================================================

    // synthesis translate_off
    initial
    begin
        if (mux_in.T_PAYLOAD_WIDTH != demux_out[0].T_PAYLOAD_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: mux_in (%0d)/demux_out (%0d) payload width mismatch!",
                   mux_in.T_PAYLOAD_WIDTH, demux_out[0].T_PAYLOAD_WIDTH);
        end

        if (mux_in.TUSER_WIDTH != demux_out[0].TUSER_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: mux_in (%0d)/demux_out (%0d) user width mismatch!",
                   mux_in.TUSER_WIDTH, demux_out[0].TUSER_WIDTH);
        end
    end
    // synthesis translate_on

endmodule // ofs_plat_prim_vchan_demux_tree
