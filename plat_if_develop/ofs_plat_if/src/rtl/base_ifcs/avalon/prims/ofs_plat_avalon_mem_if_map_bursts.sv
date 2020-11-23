//
// Copyright (c) 2019, Intel Corporation
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
// mem_source and mem_sink may differ only in the width of their burst counts.
// Map bursts requested by the source into legal bursts in the sink.
//
module ofs_plat_avalon_mem_if_map_bursts
  #(
    // Which bit in the mem_sink user flags should be set to indicate
    // injected bursts that should be dropped so that the AFU sees
    // only responses to its original bursts?
    parameter UFLAG_NO_REPLY = 0,

    // Set to non-zero if addresses in the sink must be naturally aligned to
    // the burst size.
    parameter NATURAL_ALIGNMENT = 0
    )
   (
    ofs_plat_avalon_mem_if.to_source mem_source,
    ofs_plat_avalon_mem_if.to_sink mem_sink
    );


    initial
    begin
        if (mem_source.ADDR_WIDTH_ != mem_sink.ADDR_WIDTH_)
            $fatal(2, "** ERROR ** %m: ADDR_WIDTH mismatch!");
        if (mem_source.DATA_WIDTH_ != mem_sink.DATA_WIDTH_)
            $fatal(2, "** ERROR ** %m: DATA_WIDTH mismatch!");
    end

    logic clk;
    assign clk = mem_sink.clk;
    logic reset_n;
    assign reset_n = mem_sink.reset_n;

    localparam ADDR_WIDTH = mem_source.ADDR_WIDTH_;
    localparam DATA_WIDTH = mem_source.DATA_WIDTH_;
    localparam DATA_N_BYTES = mem_source.DATA_N_BYTES;
    localparam USER_WIDTH = mem_source.USER_WIDTH;

    localparam SOURCE_BURST_WIDTH = mem_source.BURST_CNT_WIDTH_;
    localparam SINK_BURST_WIDTH = mem_sink.BURST_CNT_WIDTH_;
    typedef logic [SOURCE_BURST_WIDTH-1 : 0] t_source_burst_cnt;

    generate
        if ((! NATURAL_ALIGNMENT && (SINK_BURST_WIDTH >= SOURCE_BURST_WIDTH)) ||
            (SOURCE_BURST_WIDTH == 1))
        begin : nb
            // There is no alignment requirement and sink can handle all
            // source burst sizes. Just wire the two interfaces together.
            ofs_plat_avalon_mem_if_connect
              simple_conn
               (
                .mem_source,
                .mem_sink
                );
        end
        else
        begin : b
            //
            // Break source bursts into sink-sized bursts.
            //
            logic req_complete;
            logic m_new_req;
            logic [ADDR_WIDTH-1 : 0] s_address;
            logic [SINK_BURST_WIDTH-1 : 0] s_burstcount;
            logic [USER_WIDTH-1 : 0] m_user;
            logic m_wr_sop, s_wr_sop;

            // New flits are allowed as long as the sink isn't in waitrequest
            // and the previous read is complete. Writes aren't a problem since
            // the data flit count is the same, independent of burst sizes.
            assign mem_source.waitrequest = mem_sink.waitrequest ||
                                            (mem_sink.read && ! req_complete);

            // Ready to start a new packet burst request coming from the source?
            // Only source reads or source write SOP flits start a new request.
            assign m_new_req = ! mem_source.waitrequest && m_wr_sop;

            // Sink ready to accept request? For reads, this is easy: a request
            // may be accepted as long as the sink's waitrequest is clear.
            // Writes accept requests only in the SOP beat of sink bursts.
            logic s_accept_req;
            assign s_accept_req = ! mem_sink.waitrequest && s_wr_sop &&
                                  (mem_sink.write || mem_sink.read);

            // Map burst counts in the source to one or more bursts in the sink.
            ofs_plat_prim_burstcount1_mapping_gearbox
              #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .SOURCE_BURST_WIDTH(SOURCE_BURST_WIDTH),
                .SINK_BURST_WIDTH(SINK_BURST_WIDTH),
                .NATURAL_ALIGNMENT(NATURAL_ALIGNMENT)
                )
               gearbox
                (
                 .clk,
                 .reset_n,

                 .m_new_req,
                 .m_addr(mem_source.address),
                 .m_burstcount(mem_source.burstcount),

                 .s_accept_req,
                 .s_req_complete(req_complete),
                 .s_addr(s_address),
                 .s_burstcount(s_burstcount)
                 );

            // Register request state coming from the source that isn't held
            // in the burst count mapping gearbox.
            always_ff @(posedge clk)
            begin
                if (! mem_source.waitrequest)
                begin
                    mem_sink.read <= mem_source.read;
                    mem_sink.write <= mem_source.write;
                    mem_sink.writedata <= mem_source.writedata;
                    mem_sink.byteenable <= mem_source.byteenable;
                    if (m_wr_sop)
                    begin
                        m_user <= mem_source.user;
                    end
                end

                if (!reset_n)
                begin
                    mem_sink.read <= 1'b0;
                    mem_sink.write <= 1'b0;
                end
            end

            // Address and burstcount are valid only during the sink's SOP cycle.
            // (SOP is valid when reads arrive too, since the sink was prepared
            // to accept the SOP of a write.)
            //
            // Force 'x for debugging. (Without 'x the address and burstcount are
            // associated with the next packet, which is confusing.)
            assign mem_sink.address = s_wr_sop ? s_address : 'x;
            assign mem_sink.burstcount = s_wr_sop ? s_burstcount : 'x;

            // Responses don't encode anything about bursts. Forward them unmodified.
            assign mem_source.readdatavalid = mem_sink.readdatavalid;
            assign mem_source.readdata = mem_sink.readdata;
            assign mem_source.response = mem_sink.response;
            assign mem_source.readresponseuser = mem_sink.readresponseuser;

            // Forward only responses to source bursts. Extra sink bursts are
            // indicated by 0 in writeresponseuser[UFLAG_NO_REPLY].
            assign mem_source.writeresponsevalid =
                mem_sink.writeresponsevalid && !mem_sink.writeresponseuser[UFLAG_NO_REPLY];
            assign mem_source.writeresponse = mem_sink.writeresponse;
            assign mem_source.writeresponseuser = mem_sink.writeresponseuser;

            // Write ACKs can flow back unchanged. It is up to the part of this
            // module to ensure that there is only one write ACK per source burst.
            always_comb
            begin
                mem_sink.user = m_user;
                mem_sink.user[UFLAG_NO_REPLY] = !req_complete && mem_sink.write;
            end

            //
            // Write SOP tracking
            //

            ofs_plat_prim_burstcount1_sop_tracker
              #(
                .BURST_CNT_WIDTH(SOURCE_BURST_WIDTH)
                )
              m_sop_tracker
               (
                .clk,
                .reset_n,
                .flit_valid(mem_source.write && ! mem_source.waitrequest),
                .burstcount(mem_source.burstcount),
                .sop(m_wr_sop),
                .eop()
                );

            ofs_plat_prim_burstcount1_sop_tracker
              #(
                .BURST_CNT_WIDTH(SINK_BURST_WIDTH)
                )
              s_sop_tracker
               (
                .clk,
                .reset_n,
                .flit_valid(mem_sink.write && ! mem_sink.waitrequest),
                .burstcount(mem_sink.burstcount),
                .sop(s_wr_sop),
                .eop()
                );


            // synthesis translate_off

            //
            // Validated in simulation: confirm that the parent module is properly
            // returning writeresponseuser[UFLAG_NO_REPLY] based on
            // wr_sink.user[UFLAG_NO_REPLY] for burst tracking. The test here is
            // simple: if there are more write responses than write requests from
            // the source then something is wrong.
            //
            int m_num_writes, m_num_write_responses;

            always_ff @(posedge clk)
            begin
                if (m_num_write_responses > m_num_writes)
                begin
                    $fatal(2, "** ERROR ** %m: More write responses than write requests! Is the parent module returning writeresponseuser[%0d]?", UFLAG_NO_REPLY);
                end

                if (mem_source.write && ! mem_source.waitrequest && m_wr_sop)
                begin
                    m_num_writes <= m_num_writes + 1;
                end

                if (mem_source.writeresponsevalid)
                begin
                    m_num_write_responses <= m_num_write_responses + 1;
                end

                if (!reset_n)
                begin
                    m_num_writes <= 0;
                    m_num_write_responses <= 0;
                end
            end

            // synthesis translate_on
        end
    endgenerate

endmodule // ofs_plat_avalon_mem_if_map_bursts
