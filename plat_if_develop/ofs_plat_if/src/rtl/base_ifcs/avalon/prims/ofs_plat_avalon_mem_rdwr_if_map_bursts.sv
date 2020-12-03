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
// mem_source and mem_sink may differ only in the width of their burst counts.
// Map bursts requested by the source into legal bursts in the sink.
//
module ofs_plat_avalon_mem_rdwr_if_map_bursts
  #(
    // Which bit in the mem_sink user flags should be set to indicate
    // injected bursts that should be dropped so that the AFU sees
    // only responses to its original bursts?
    parameter UFLAG_NO_REPLY = 0,

    // Set to non-zero if addresses in the sink must be naturally aligned to
    // the burst size.
    parameter NATURAL_ALIGNMENT = 0,

    // Set to a page size (bytes) if the sink must avoid bursts that cross pages.
    parameter PAGE_SIZE = 0
    )
   (
    ofs_plat_avalon_mem_rdwr_if.to_source mem_source,
    ofs_plat_avalon_mem_rdwr_if.to_sink mem_sink
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

    localparam SOURCE_BURST_WIDTH = mem_source.BURST_CNT_WIDTH_;
    localparam SINK_BURST_WIDTH = mem_sink.BURST_CNT_WIDTH_;
    typedef logic [SOURCE_BURST_WIDTH-1 : 0] t_source_burst_cnt;

    localparam USER_WIDTH = mem_sink.USER_WIDTH_;
    typedef logic [USER_WIDTH-1 : 0] t_user;

    generate
        if ((!NATURAL_ALIGNMENT && !PAGE_SIZE && (SINK_BURST_WIDTH >= SOURCE_BURST_WIDTH)) ||
            (SOURCE_BURST_WIDTH == 1))
        begin : nb
            // There is no alignment requirement and sink can handle all
            // source burst sizes. Just wire the two interfaces together.
            ofs_plat_avalon_mem_rdwr_if_connect
              simple_conn
               (
                .mem_source,
                .mem_sink
                );
        end
        else
        begin : b
            //
            // Reads
            //

            logic rd_complete;
            logic rd_next;
            assign mem_source.rd_waitrequest = ! rd_next;

            // Ready to start a new read request coming from the source? Yes if
            // there is no current request or the previous one is complete.
            assign rd_next = ! mem_sink.rd_waitrequest && (! mem_sink.rd_read || rd_complete);

            // Map burst counts in the source to one or more bursts in the sink.
            ofs_plat_prim_burstcount1_mapping_gearbox
              #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .SOURCE_BURST_WIDTH(SOURCE_BURST_WIDTH),
                .SINK_BURST_WIDTH(SINK_BURST_WIDTH),
                .NATURAL_ALIGNMENT(NATURAL_ALIGNMENT),
                // Map page size to lines
                .PAGE_SIZE(PAGE_SIZE / (DATA_WIDTH / 8))
                )
               rd_gearbox
                (
                 .clk,
                 .reset_n,

                 .m_new_req(rd_next && mem_source.rd_read),
                 .m_addr(mem_source.rd_address),
                 .m_burstcount(mem_source.rd_burstcount),

                 .s_accept_req(mem_sink.rd_read && ! mem_sink.rd_waitrequest),
                 .s_req_complete(rd_complete),
                 .s_addr(mem_sink.rd_address),
                 .s_burstcount(mem_sink.rd_burstcount)
                 );

            // Register read request state coming from the source that isn't held
            // in the burst count mapping gearbox.
            always_ff @(posedge clk)
            begin
                if (rd_next)
                begin
                    // New request -- the last one is complete
                    mem_sink.rd_read <= mem_source.rd_read;
                    mem_sink.rd_byteenable <= mem_source.rd_byteenable;
                    mem_sink.rd_user <= mem_source.rd_user;
                end

                if (!reset_n)
                begin
                    mem_sink.rd_read <= 1'b0;
                end
            end

            // Responses don't encode anything about bursts. Forward them unmodified.
            assign mem_source.rd_readdata = mem_sink.rd_readdata;
            assign mem_source.rd_readdatavalid = mem_sink.rd_readdatavalid;
            assign mem_source.rd_response = mem_sink.rd_response;
            assign mem_source.rd_readresponseuser = mem_sink.rd_readresponseuser;


            //
            // Writes
            //

            logic wr_complete;
            assign mem_source.wr_waitrequest = mem_sink.wr_waitrequest;

            logic [ADDR_WIDTH-1 : 0] s_wr_address;
            logic [SINK_BURST_WIDTH-1 : 0] s_wr_burstcount;
            logic m_wr_sop, s_wr_sop;
            t_user s_wr_user;

            // Map burst counts in the source to one or more bursts in the sink.
            ofs_plat_prim_burstcount1_mapping_gearbox
              #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .SOURCE_BURST_WIDTH(SOURCE_BURST_WIDTH),
                .SINK_BURST_WIDTH(SINK_BURST_WIDTH),
                .NATURAL_ALIGNMENT(NATURAL_ALIGNMENT),
                // Map page size to lines
                .PAGE_SIZE(PAGE_SIZE / (DATA_WIDTH / 8))
                )
               wr_gearbox
                (
                 .clk,
                 .reset_n,

                 .m_new_req(mem_source.wr_write && ! mem_sink.wr_waitrequest && m_wr_sop),
                 .m_addr(mem_source.wr_address),
                 .m_burstcount(mem_source.wr_burstcount),

                 .s_accept_req(mem_sink.wr_write && ! mem_sink.wr_waitrequest && s_wr_sop),
                 .s_req_complete(wr_complete),
                 .s_addr(s_wr_address),
                 .s_burstcount(s_wr_burstcount)
                 );

            // Address and burstcount are valid only during the sink's SOP cycle.
            // Force 'x for debugging. (Without 'x the address and burstcount are
            // associated with the next packet, which is confusing.)
            assign mem_sink.wr_address = s_wr_sop ? s_wr_address : 'x;
            assign mem_sink.wr_burstcount = s_wr_sop ? s_wr_burstcount : 'x;

            // Register write request state coming from the source that isn't held
            // in the burst count mapping gearbox.
            always_ff @(posedge clk)
            begin
                if (! mem_sink.wr_waitrequest)
                begin
                    // New request -- the last one is complete
                    mem_sink.wr_write <= mem_source.wr_write;
                    mem_sink.wr_writedata <= mem_source.wr_writedata;
                    mem_sink.wr_byteenable <= mem_source.wr_byteenable;
                    if (m_wr_sop)
                    begin
                        s_wr_user <= mem_source.wr_user;
                    end
                end

                if (!reset_n)
                begin
                    mem_sink.wr_write <= 1'b0;
                end
            end

            // Write ACKs can flow back unchanged. It is up to the part of this
            // module to ensure that there is only one write ACK per source burst.
            always_comb
            begin
                mem_sink.wr_user = s_wr_user;
                mem_sink.wr_user[UFLAG_NO_REPLY] = !(wr_complete && s_wr_sop) || s_wr_user[UFLAG_NO_REPLY];
            end

            ofs_plat_prim_burstcount1_sop_tracker
              #(
                .BURST_CNT_WIDTH(SOURCE_BURST_WIDTH)
                )
              m_sop_tracker
               (
                .clk,
                .reset_n,
                .flit_valid(mem_source.wr_write && ! mem_source.wr_waitrequest),
                .burstcount(mem_source.wr_burstcount),
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
                .flit_valid(mem_sink.wr_write && ! mem_sink.wr_waitrequest),
                .burstcount(mem_sink.wr_burstcount),
                .sop(s_wr_sop),
                .eop()
                );

            // Forward only responses to source bursts. Extra sink bursts are
            // indicated by 1 in wr_writeresponseuser[UFLAG_NO_REPLY].
            assign mem_source.wr_writeresponsevalid =
                mem_sink.wr_writeresponsevalid && !mem_sink.wr_writeresponseuser[UFLAG_NO_REPLY];
            assign mem_source.wr_response = mem_sink.wr_response;
            assign mem_source.wr_writeresponseuser = mem_sink.wr_writeresponseuser;


            // synthesis translate_off

            //
            // Validated in simulation: confirm that the sink is properly
            // returning wr_writeresponseuser[UFLAG_NO_REPLY] based on
            // wr_sink.wr_user[UFLAG_NO_REPLY] for burst tracking. The test here is
            // simple: if there are more write responses than write requests from the
            // source then something is wrong.
            //
            int m_num_writes, m_num_write_responses;

            always_ff @(posedge clk)
            begin
                if (m_num_write_responses > m_num_writes)
                begin
                    $fatal(2, "** ERROR ** %m: More write responses than write requests! Is the sink returning wr_writeresponseuser[%0d]?", UFLAG_NO_REPLY);
                end

                if (mem_source.wr_write && ! mem_source.wr_waitrequest && m_wr_sop)
                begin
                    m_num_writes <= m_num_writes + 1;
                end

                if (mem_source.wr_writeresponsevalid)
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

endmodule // ofs_plat_avalon_mem_rdwr_if_map_bursts
