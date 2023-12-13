// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


`include "ofs_plat_if.vh"

module ofs_plat_host_chan_@group@_from_host_chan
   (
    ofs_plat_host_chan_axis_pcie_tlp_if to_fiu0,
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_afu
    );

    localparam FIU_TDATA_WIDTH = ofs_plat_host_chan_fim_gasket_pkg::TDATA_WIDTH;
    localparam AFU_TDATA_WIDTH = ofs_plat_host_chan_@group@_fim_gasket_pkg::TDATA_WIDTH;

    localparam FIU_TKEEP_WIDTH = FIU_TDATA_WIDTH / 8;
    localparam AFU_TKEEP_WIDTH = AFU_TDATA_WIDTH / 8;

    assign to_afu.clk = to_fiu0.clk;
    assign to_afu.reset_n = to_fiu0.reset_n;
    assign to_afu.instance_number = to_fiu0.instance_number;

    assign to_afu.pf_num = to_fiu0.pf_num;
    assign to_afu.vf_num = to_fiu0.vf_num;
    assign to_afu.vf_active = to_fiu0.vf_active;

    ofs_plat_host_chan_from_@group@_chan tx_a
       (
        .source(to_afu.afu_tx_a_st),
        .sink(to_fiu0.afu_tx_a_st)
        );

    ofs_plat_host_chan_from_@group@_chan tx_b
       (
        .source(to_afu.afu_tx_b_st),
        .sink(to_fiu0.afu_tx_b_st)
        );

    ofs_plat_host_chan_to_@group@_chan rx_a
       (
        .source(to_fiu0.afu_rx_a_st),
        .sink(to_afu.afu_rx_a_st)
        );

    ofs_plat_host_chan_to_@group@_chan rx_b
       (
        .source(to_fiu0.afu_rx_b_st),
        .sink(to_afu.afu_rx_b_st)
        );

endmodule // ofs_plat_host_chan_@group@_from_host_chan


//
// RX direction: narrow to wide channel.
//
module ofs_plat_host_chan_to_@group@_chan
   (
    ofs_plat_axi_stream_if.to_source source,
    ofs_plat_axi_stream_if.to_sink   sink
    );

    wire clk = source.clk;
    wire reset_n = source.reset_n;

    // Skid buffer for source timing
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser)
        )
      source_skid();

    ofs_plat_axi_stream_if_skid_source_clk skid_in
       (
        .stream_source(source),
        .stream_sink(source_skid)
        );

    ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata source_prev_tdata;
    ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser source_prev_tuser;
    logic source_prev_valid;

    assign source_skid.tready = sink.tready || (!source_skid.t.last && !source_prev_valid);
    assign sink.tvalid = source_skid.tvalid && (source_skid.t.last || source_prev_valid);
    always_comb
    begin
        sink.t.last = source_skid.t.last;

        if (source_prev_valid)
        begin
            sink.t.keep = { source_skid.t.keep, {$bits(source_skid.t.keep){1'b1}} };
            sink.t.data = { source_skid.t.data, source_prev_tdata };
            sink.t.user = source_prev_tuser;
            sink.t.user[0].eop = source_skid.t.user[0].eop;
        end
        else
        begin
            sink.t.keep = { '0, source_skid.t.keep };
            sink.t.data = { '0, source_skid.t.data };
            sink.t.user = source_skid.t.user;
        end
    end

    always_ff @(posedge clk)
    begin
        if (source_skid.tvalid && source_skid.tready)
        begin
            source_prev_tdata <= source_skid.t.data;
            source_prev_tuser <= source_skid.t.user;
            source_prev_valid <= !sink.tvalid;
        end

        if (!reset_n)
        begin
            source_prev_valid <= 1'b0;
        end
    end

endmodule // ofs_plat_host_chan_to_@group@_chan


//
// TX direction: wide to narrow channel.
//
module ofs_plat_host_chan_from_@group@_chan
   (
    ofs_plat_axi_stream_if.to_source source,
    ofs_plat_axi_stream_if.to_sink   sink
    );

    wire clk = source.clk;
    wire reset_n = source.reset_n;

    localparam TKEEP_BITS_HALF = $bits(source.t.keep) / 2;
    localparam TDATA_BITS_HALF = $bits(source.t.data) / 2;
    wire source_high_empty = ~source.t.keep[TKEEP_BITS_HALF];

    // Skid buffer for sink timing
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser)
        )
      sink_skid();

    ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata source_prev_tdata;
    ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tkeep source_prev_tkeep;
    ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser source_prev_tuser;
    logic source_prev_valid;

    assign source.tready = sink_skid.tready && !source_prev_valid;
    assign sink_skid.tvalid = source.tvalid || source_prev_valid;
    always_comb
    begin
        if (source_prev_valid)
        begin
            sink_skid.t.last = source_prev_tuser[0].eop;
            sink_skid.t.keep = source_prev_tkeep;
            sink_skid.t.data = source_prev_tdata;
            sink_skid.t.user = source_prev_tuser;
            sink_skid.t.user[0].sop = 1'b0;
        end
        else
        begin
            sink_skid.t.last = source.t.last && source_high_empty;
            sink_skid.t.keep = source.t.keep[0 +: TKEEP_BITS_HALF];
            sink_skid.t.data = source.t.data[0 +: TDATA_BITS_HALF];
            sink_skid.t.user = source.t.user;
            sink_skid.t.user[0].eop = sink_skid.t.last;
        end
    end

    always_ff @(posedge clk)
    begin
        if (sink_skid.tready)
            source_prev_valid <= 1'b0;

        if (source.tvalid && source.tready)
        begin
            source_prev_tkeep <= source.t.keep[TKEEP_BITS_HALF +: TKEEP_BITS_HALF];
            source_prev_tdata <= source.t.data[TDATA_BITS_HALF +: TDATA_BITS_HALF];
            source_prev_tuser <= source.t.user;
            source_prev_valid <= !sink_skid.t.last;
        end

        if (!reset_n)
        begin
            source_prev_valid <= 1'b0;
        end
    end

    ofs_plat_axi_stream_if_skid_sink_clk skid_out
       (
        .stream_source(sink_skid),
        .stream_sink(sink)
        );

endmodule // ofs_plat_host_chan_from_@group@_chan
