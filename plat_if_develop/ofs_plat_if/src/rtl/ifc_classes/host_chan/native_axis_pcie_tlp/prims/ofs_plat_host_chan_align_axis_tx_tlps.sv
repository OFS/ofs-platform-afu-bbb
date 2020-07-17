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
// Transform the master TLP vector to a slave vector. The slave may have
// a different number of channels than the master.
//
// *** When NUM_SLAVE_TLP_CH is less than NUM_MASTER_TLP_CH, the master
// *** stream is broken into multiple cycles. The code here assumes that
// *** valid master channels are packed densely in low channels.
//

module ofs_plat_host_chan_align_axis_tx_tlps
  #(
    parameter NUM_MASTER_TLP_CH = 2,
    parameter NUM_SLAVE_TLP_CH = 2,

    parameter type TDATA_TYPE,
    parameter type TUSER_TYPE
    )
   (
    ofs_plat_axi_stream_if.to_master stream_master,
    ofs_plat_axi_stream_if.to_slave stream_slave
    );

    logic clk;
    assign clk = stream_master.clk;
    logic reset_n;
    assign reset_n = stream_master.reset_n;

    typedef TDATA_TYPE [NUM_MASTER_TLP_CH-1 : 0] t_master_tdata_vec;
    typedef TUSER_TYPE [NUM_MASTER_TLP_CH-1 : 0] t_master_tuser_vec;

    typedef TDATA_TYPE [NUM_SLAVE_TLP_CH-1 : 0] t_slave_tdata_vec;
    typedef TUSER_TYPE [NUM_SLAVE_TLP_CH-1 : 0] t_slave_tuser_vec;


    generate
        if (NUM_MASTER_TLP_CH <= NUM_SLAVE_TLP_CH)
        begin : w
            // All master channels fit in the set of slave channels.
            // Just wire them together. If there are extra slave
            // channels then tie them off since there is nothing
            // to feed them.

            always_comb
            begin
                stream_master.tready = stream_slave.tready;

                stream_slave.tvalid = stream_master.tvalid;
                stream_slave.t.last = stream_master.t.last;
                stream_slave.t.user = { '0, stream_master.t.user };
                stream_slave.t.data = { '0, stream_master.t.data };
            end
        end
        else
        begin : m
            // More source than destination channels. A more complicated
            // mapping is required.

            // Add a skid buffer on input for timing
            ofs_plat_axi_stream_if
              #(
                .TDATA_TYPE(t_master_tdata_vec),
                .TUSER_TYPE(t_master_tuser_vec)
                )
              master_skid();

            ofs_plat_axi_stream_if_skid_master_clk entry_skid
               (
                .stream_master(stream_master),
                .stream_slave(master_skid)
                );

            // Next channel to consume from master
            logic [$clog2(NUM_MASTER_TLP_CH)-1 : 0] master_chan_next;

            // Will the full message from master channels be complete
            // after the current subset is forwarded to the slave?
            logic master_not_complete;

            always_comb
            begin
                master_not_complete = 1'b0;
                for (int c = NUM_SLAVE_TLP_CH + master_chan_next; c < NUM_MASTER_TLP_CH; c = c + 1)
                begin
                    master_not_complete = master_not_complete || master_skid.t.data[c].valid;
                end
            end

            // Outbound from master is ready if the slave is ready and the full
            // message is complete.
            logic slave_ready;
            assign master_skid.tready = slave_ready && !master_not_complete;
            
            always_ff @(posedge clk)
            begin
                if (slave_ready)
                begin
                    if (master_skid.tvalid && master_not_complete)
                    begin
                        master_chan_next <= master_chan_next + NUM_SLAVE_TLP_CH;
                    end
                    else
                    begin
                        master_chan_next <= '0;
                    end
                end

                if (!reset_n)
                begin
                    master_chan_next <= '0;
                end
            end

            //
            // Forward a slave-sized chunk of channels.
            //
            assign slave_ready = stream_slave.tready || !stream_slave.tvalid;

            always_ff @(posedge clk)
            begin
                if (slave_ready)
                begin
                    stream_slave.tvalid <= master_skid.tvalid;
                    stream_slave.t.last <= master_skid.t.last && !master_not_complete;

                    for (int i = 0; i < NUM_SLAVE_TLP_CH; i = i + 1)
                    begin
                        if (i + master_chan_next < NUM_MASTER_TLP_CH)
                        begin
                            stream_slave.t.data[i] <= master_skid.t.data[i + master_chan_next];
                            stream_slave.t.user[i] <= master_skid.t.user[i + master_chan_next];
                        end
                        else
                        begin
                            stream_slave.t.data[i].valid <= 1'b0;
                            stream_slave.t.data[i].sop <= 1'b0;
                            stream_slave.t.data[i].eop <= 1'b0;
                        end
                    end
                end

                if (!reset_n)
                begin
                    stream_slave.tvalid <= 1'b0;
                end
            end
        end
    endgenerate

endmodule // ofs_plat_host_chan_align_axis_tx_tlps
