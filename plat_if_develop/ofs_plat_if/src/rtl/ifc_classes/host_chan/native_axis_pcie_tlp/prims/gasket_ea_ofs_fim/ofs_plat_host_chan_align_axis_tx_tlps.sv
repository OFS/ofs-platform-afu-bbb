// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


//
// Transform the source TLP vector to a sink vector. The sink may have
// a different number of channels than the source.
//
// *** When NUM_SINK_TLP_CH is less than NUM_SOURCE_TLP_CH, the source
// *** stream is broken into multiple cycles. The code here assumes that
// *** valid source channels are packed densely in low channels.
//

module ofs_plat_host_chan_align_axis_tx_tlps
  #(
    parameter NUM_SOURCE_TLP_CH = 2,
    parameter NUM_SINK_TLP_CH = 2,

    parameter type TDATA_TYPE,
    parameter type TUSER_TYPE
    )
   (
    ofs_plat_axi_stream_if.to_source stream_source,
    ofs_plat_axi_stream_if.to_sink stream_sink
    );

    logic clk;
    assign clk = stream_source.clk;
    logic reset_n;
    assign reset_n = stream_source.reset_n;

    typedef TDATA_TYPE [NUM_SOURCE_TLP_CH-1 : 0] t_source_tdata_vec;
    typedef TUSER_TYPE [NUM_SOURCE_TLP_CH-1 : 0] t_source_tuser_vec;

    typedef TDATA_TYPE [NUM_SINK_TLP_CH-1 : 0] t_sink_tdata_vec;
    typedef TUSER_TYPE [NUM_SINK_TLP_CH-1 : 0] t_sink_tuser_vec;


    generate
        if (NUM_SOURCE_TLP_CH <= NUM_SINK_TLP_CH)
        begin : w
            // All source channels fit in the set of sink channels.
            // Just connect them with a skid buffer. If there are extra
            // sink channels then tie them off since there is nothing
            // to feed them.

            ofs_plat_axi_stream_if
              #(
                .TDATA_TYPE(t_sink_tdata_vec),
                .TUSER_TYPE(t_sink_tuser_vec)
                )
              sink_skid();

            always_comb
            begin
                stream_source.tready = sink_skid.tready;

                sink_skid.tvalid = stream_source.tvalid;
                sink_skid.t.last = stream_source.t.last;
                sink_skid.t.user = { '0, stream_source.t.user };
                sink_skid.t.data = { '0, stream_source.t.data };
            end

            ofs_plat_axi_stream_if_skid_sink_clk skid
               (
                .stream_source(sink_skid),
                .stream_sink
                );
        end
        else
        begin : m
            // More source than destination channels. A more complicated
            // mapping is required.

            // Add a skid buffer on input for timing
            ofs_plat_axi_stream_if
              #(
                .TDATA_TYPE(t_source_tdata_vec),
                .TUSER_TYPE(t_source_tuser_vec)
                )
              source_skid();

            ofs_plat_axi_stream_if_skid_source_clk entry_skid
               (
                .stream_source(stream_source),
                .stream_sink(source_skid)
                );

            // Next channel to consume from source
            logic [$clog2(NUM_SOURCE_TLP_CH)-1 : 0] source_chan_next;

            // Will the full message from source channels be complete
            // after the current subset is forwarded to the sink?
            logic source_not_complete;

            always_comb
            begin
                source_not_complete = 1'b0;
                for (int c = NUM_SINK_TLP_CH + source_chan_next; c < NUM_SOURCE_TLP_CH; c = c + 1)
                begin
                    source_not_complete = source_not_complete || source_skid.t.data[c].valid;
                end
            end

            // Outbound from source is ready if the sink is ready and the full
            // message is complete.
            logic sink_ready;
            assign source_skid.tready = sink_ready && !source_not_complete;
            
            always_ff @(posedge clk)
            begin
                if (sink_ready)
                begin
                    if (source_skid.tvalid && source_not_complete)
                    begin
                        source_chan_next <= source_chan_next + NUM_SINK_TLP_CH;
                    end
                    else
                    begin
                        source_chan_next <= '0;
                    end
                end

                if (!reset_n)
                begin
                    source_chan_next <= '0;
                end
            end

            //
            // Forward a sink-sized chunk of channels.
            //
            assign sink_ready = stream_sink.tready || !stream_sink.tvalid;

            always_ff @(posedge clk)
            begin
                if (sink_ready)
                begin
                    stream_sink.tvalid <= source_skid.tvalid;
                    stream_sink.t.last <= source_skid.t.last && !source_not_complete;

                    for (int i = 0; i < NUM_SINK_TLP_CH; i = i + 1)
                    begin
                        if (i + source_chan_next < NUM_SOURCE_TLP_CH)
                        begin
                            stream_sink.t.data[i] <= source_skid.t.data[i + source_chan_next];
                            stream_sink.t.user[i] <= source_skid.t.user[i + source_chan_next];
                        end
                        else
                        begin
                            stream_sink.t.data[i].valid <= 1'b0;
                            stream_sink.t.data[i].sop <= 1'b0;
                            stream_sink.t.data[i].eop <= 1'b0;
                        end
                    end
                end

                if (!reset_n)
                begin
                    stream_sink.tvalid <= 1'b0;
                end
            end
        end
    endgenerate

endmodule // ofs_plat_host_chan_align_axis_tx_tlps
