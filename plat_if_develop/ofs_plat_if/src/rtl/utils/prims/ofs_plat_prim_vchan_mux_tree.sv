// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Combine incoming per-channel streams into a single multiplexed
// stream, potentially using a tree if the switched bus is too wide.
//
// No virtual channel tags are added here. The streams must be
// tagged internally with the matching port index by whatever
// generates the stream data.
//

`include "ofs_plat_if.vh"

module ofs_plat_prim_vchan_mux_tree
  #(
    parameter NUM_DEMUX_PORTS = 2,
    parameter MAX_SWITCHED_DATA_WIDTH = 4096,
    parameter MAX_PORTS_PER_LEVEL = 8
    )
   (
    ofs_plat_axi_stream_if.to_source demux_in[NUM_DEMUX_PORTS],
    ofs_plat_axi_stream_if.to_sink mux_out
    );

    wire clk = mux_out.clk;
    wire reset_n = mux_out.reset_n;

    localparam M_OUT_DATA_WIDTH = mux_out.TDATA_WIDTH;

    // Number of ports that fit in the max switched data width.
    // Minimum 2 to form a tree.
    localparam PORTS_PER_LEVEL_BASE = MAX_SWITCHED_DATA_WIDTH / M_OUT_DATA_WIDTH;
    // Ports per level, bounded by 2 and MAX_PORTS_PER_LEVEL.
    localparam PORTS_PER_LEVEL =
        PORTS_PER_LEVEL_BASE <= 2 ? 2 :
            ((PORTS_PER_LEVEL_BASE >= MAX_PORTS_PER_LEVEL) ? MAX_PORTS_PER_LEVEL :
                                                             PORTS_PER_LEVEL_BASE);

    // Each layer within the tree has its own round-robin arbitration.
    // Try to balance the tree so that arbitration remains fair throughout
    // by picking a given level's number of ports with the goal of minimizing
    // the difference in number of children per port.
    //
    // Pick the number of ports, less than max_arb_ports, that minimizes
    // the remainder when dividing num_demux_ports. There is probably a
    // more efficient way to find this, but it is static elaboration and
    // the number of ports is small.
    function automatic int pick_fair_num_ports(int max_arb_ports, int num_demux_ports);
        int best_num_ports = max_arb_ports;
        int best_rem = num_demux_ports % max_arb_ports;

        for (int i = max_arb_ports-1; i > 1; i -= 1) begin
            int rem = num_demux_ports % i;
            if (rem < best_rem) begin
                best_num_ports = i;
                best_rem = rem;
            end
        end

        return best_num_ports;
    endfunction // pick_fair_num_ports

    if (NUM_DEMUX_PORTS == 1) begin : direct

        // Only 1 input port! Just wire the input to the output.
        ofs_plat_axi_stream_if_connect
            conn (.stream_source(demux_in[0]), .stream_sink(mux_out));

    end
    else if (NUM_DEMUX_PORTS <= PORTS_PER_LEVEL) begin : mux

        // Fanin is low enough. Generate the target MUX.
        ofs_plat_prim_vchan_mux
          #(
            .NUM_DEMUX_PORTS(NUM_DEMUX_PORTS)
            )
          m
           (
            .demux_in,
            .mux_out
            );

    end
    else begin : tree

        //
        // High fanin case. Add an intermediate node with NUM_TREE_PORTS
        // ports, distributing the full incoming demux set across them.
        // Then recursively instantiate a MUX for each cluster.
        //

        localparam NUM_TREE_PORTS = pick_fair_num_ports(PORTS_PER_LEVEL, NUM_DEMUX_PORTS);

        ofs_plat_axi_stream_if
          #(
            .TDATA_TYPE(logic [mux_out.TDATA_WIDTH-1:0]),
            .TUSER_TYPE(logic [mux_out.TUSER_WIDTH-1:0])
            )
          tree_demux_in[NUM_TREE_PORTS]();

        // Spread the full set of demux_in ports across the NUM_TREE_PORTS
        // intermediate ports. We know that NUM_DEMUX_PORTS > NUM_TREE_PORTS
        // here.
        localparam DEMUX_IN_PER_PORT = NUM_DEMUX_PORTS / NUM_TREE_PORTS;

        for (genvar i = 0; i < NUM_TREE_PORTS; i += 1) begin : t
            assign tree_demux_in[i].clk = clk;
            assign tree_demux_in[i].reset_n = reset_n;
            assign tree_demux_in[i].instance_number = mux_out.instance_number;

            // For all but the last instance, map DEMUX_IN_PER_PORT to
            // tree_demux_in[i]. The last port maps whatever remains.
            localparam ITER_NUM_DEMUX_PORTS =
                (i == NUM_TREE_PORTS - 1) ? (NUM_DEMUX_PORTS - i * DEMUX_IN_PER_PORT)
                                           : DEMUX_IN_PER_PORT;

            ofs_plat_prim_vchan_mux_tree
              #(
                .NUM_DEMUX_PORTS(ITER_NUM_DEMUX_PORTS),
                .MAX_SWITCHED_DATA_WIDTH(MAX_SWITCHED_DATA_WIDTH)
                )
              node
               (
                .demux_in(demux_in[i * DEMUX_IN_PER_PORT +: ITER_NUM_DEMUX_PORTS]),
                .mux_out(tree_demux_in[i])
                );
        end

        // Demultiplex the intermediate tree nodes to output
        ofs_plat_prim_vchan_mux
          #(
            .NUM_DEMUX_PORTS(NUM_TREE_PORTS)
            )
          m
           (
            .demux_in(tree_demux_in),
            .mux_out
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
        if (M_OUT_DATA_WIDTH != demux_in[0].TDATA_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: mux_out (%0d)/demux_in (%0d) width mismatch!",
                   M_OUT_DATA_WIDTH, demux_in[0].TDATA_WIDTH);
        end
    end
    // synthesis translate_on

endmodule // ofs_plat_prim_vchan_mux_tree
