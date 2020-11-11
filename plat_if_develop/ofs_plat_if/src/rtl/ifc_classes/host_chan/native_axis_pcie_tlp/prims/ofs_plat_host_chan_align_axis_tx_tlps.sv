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
            // Just wire them together. If there are extra sink
            // channels then tie them off since there is nothing
            // to feed them.

            always_comb
            begin
                stream_source.tready = stream_sink.tready;

                stream_sink.tvalid = stream_source.tvalid;
                stream_sink.t.last = stream_source.t.last;
                stream_sink.t.user = { '0, stream_source.t.user };
                stream_sink.t.data = { '0, stream_source.t.data };
            end
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
