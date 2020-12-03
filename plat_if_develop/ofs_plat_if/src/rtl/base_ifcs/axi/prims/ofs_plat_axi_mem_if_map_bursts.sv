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
// Map bursts requested by the source into legal bursts in the sink.
//
module ofs_plat_axi_mem_if_map_bursts
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
    ofs_plat_axi_mem_if.to_source mem_source,
    ofs_plat_axi_mem_if.to_sink mem_sink
    );

    logic clk;
    assign clk = mem_sink.clk;
    logic reset_n;
    assign reset_n = mem_sink.reset_n;

    localparam SOURCE_BURST_WIDTH = mem_source.BURST_CNT_WIDTH_;
    localparam SINK_BURST_WIDTH = mem_sink.BURST_CNT_WIDTH_;

    generate
        if ((!NATURAL_ALIGNMENT && !PAGE_SIZE && (SINK_BURST_WIDTH >= SOURCE_BURST_WIDTH)) ||
            (SOURCE_BURST_WIDTH == 1))
        begin : nb
            // There is no alignment requirement and sink can handle all
            // source burst sizes. Just wire the two interfaces together.
            ofs_plat_axi_mem_if_connect_by_field
              simple_conn
               (
                .mem_source,
                .mem_sink
                );
        end
        else
        begin : b
            ofs_plat_axi_mem_if
              #(
                `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_sink)
                )
              sink_burst_if();

            assign sink_burst_if.clk = mem_sink.clk;
            assign sink_burst_if.reset_n = mem_sink.reset_n;
            assign sink_burst_if.instance_number = mem_sink.instance_number;

            ofs_plat_axi_mem_if_map_bursts_impl
              #(
                .UFLAG_NO_REPLY(UFLAG_NO_REPLY),
                .NATURAL_ALIGNMENT(NATURAL_ALIGNMENT),
                .PAGE_SIZE(PAGE_SIZE)
                )
              mapper
               (
                .mem_source,
                .mem_sink(sink_burst_if)
                );

            // When bursts are broken up the last flag on write data needs
            // to be set at the end of new packets.
            ofs_plat_axi_mem_if_fixup_wlast
              fixup_wlast
               (
                .mem_source(sink_burst_if),
                .mem_sink
                );
        end
    endgenerate

endmodule // ofs_plat_axi_mem_if_map_bursts


//
// Internal implementation of burst mapping. The WLAST flag is NOT set
// correctly in the write data stream as bursts are added and must be
// fixed up by the parent.
//
module ofs_plat_axi_mem_if_map_bursts_impl
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
    ofs_plat_axi_mem_if.to_source mem_source,
    ofs_plat_axi_mem_if.to_sink mem_sink
    );

    logic clk;
    assign clk = mem_sink.clk;
    logic reset_n;
    assign reset_n = mem_sink.reset_n;

    // We only care about the address portion that is the line index
    localparam ADDR_WIDTH = mem_source.ADDR_LINE_IDX_WIDTH;
    localparam ADDR_START = mem_source.ADDR_BYTE_IDX_WIDTH;
    localparam DATA_WIDTH = mem_source.DATA_WIDTH_;

    localparam SOURCE_BURST_WIDTH = mem_source.BURST_CNT_WIDTH_;
    localparam SINK_BURST_WIDTH = mem_sink.BURST_CNT_WIDTH_;
    typedef logic [SOURCE_BURST_WIDTH-1 : 0] t_source_burst_cnt;

    // Instantiate an interface to use the properly sized internal structs
    // as registers.
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_source),
        .DISABLE_CHECKER(1)
        )
        mem_source_reg();

    //
    // Reads
    //

    logic rd_complete;
    logic rd_next;
    assign mem_source.arready = rd_next;

    logic [ADDR_WIDTH-1 : 0] s_rd_address;
    logic [SINK_BURST_WIDTH-1 : 0] s_rd_burstcount;

    // Ready to start a new read request coming from the source? Yes if
    // there is no current request or the previous one is complete.
    assign rd_next = mem_sink.arready && (!mem_sink.arvalid || rd_complete);

    // Map burst counts in the source to one or more bursts in the sink.
    ofs_plat_prim_burstcount0_mapping_gearbox
      #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .SOURCE_BURST_WIDTH(SOURCE_BURST_WIDTH),
        .SINK_BURST_WIDTH(SINK_BURST_WIDTH),
        .NATURAL_ALIGNMENT(NATURAL_ALIGNMENT),
        // Map page size to lines
        .PAGE_SIZE(PAGE_SIZE >> ADDR_START)
        )
       rd_gearbox
        (
         .clk,
         .reset_n,

         .m_new_req(rd_next && mem_source.arvalid),
         .m_addr(mem_source.ar.addr[ADDR_START +: ADDR_WIDTH]),
         .m_burstcount(mem_source.ar.len),

         .s_accept_req(mem_sink.arvalid && mem_sink.arready),
         .s_req_complete(rd_complete),
         .s_addr(s_rd_address),
         .s_burstcount(s_rd_burstcount)
         );

    always_comb
    begin
        // Use field-by-field copy since data widths may be different
        `OFS_PLAT_AXI_MEM_IF_COPY_AR(mem_sink.ar, =, mem_source_reg.ar);

        mem_sink.ar.addr[ADDR_START +: ADDR_WIDTH] = s_rd_address;
        mem_sink.ar.len = s_rd_burstcount;

        // Set a bit in ar.user to indicate whether a read
        // request is from the source (and thus completes a source
        // read request) or is generated here and should not get an
        // r.last tag.
        mem_sink.ar.user[UFLAG_NO_REPLY] = !rd_complete || mem_source_reg.ar.user[UFLAG_NO_REPLY];
    end

    // Register read request state coming from the source that isn't held
    // in the burst count mapping gearbox.
    always_ff @(posedge clk)
    begin
        if (rd_next)
        begin
            // New request -- the last one is complete
            mem_sink.arvalid <= mem_source.arvalid;
            mem_source_reg.ar <= mem_source.ar;
        end

        if (!reset_n)
        begin
            mem_sink.arvalid <= 1'b0;
        end
    end

    // Read responses
    assign mem_sink.rready = mem_source.rready;

    always_ff @(posedge clk)
    begin
        if (mem_source.rready)
        begin
            mem_source.rvalid <= mem_sink.rvalid;

            // Use field-by-field copy since data widths may be different
            `OFS_PLAT_AXI_MEM_IF_COPY_R(mem_source.r, <=, mem_sink.r);

            // Don't mark end of burst unless it corresponds to a source burst
            mem_source.r.last <= mem_sink.r.last &&
                                 !mem_sink.r.user[UFLAG_NO_REPLY];
        end

        if (!reset_n)
        begin
            mem_source.rvalid <= 1'b0;
        end
    end


    //
    // Writes
    //

    logic wr_complete;
    logic wr_next;
    assign mem_source.awready = wr_next;

    logic [ADDR_WIDTH-1 : 0] s_wr_address;
    logic [SINK_BURST_WIDTH-1 : 0] s_wr_burstcount;

    // Ready to start a new write request coming from the source? Yes if
    // there is no current request or the previous one is complete.
    assign wr_next = mem_sink.awready && (!mem_sink.awvalid || wr_complete);

    // Map burst counts in the source to one or more bursts in the sink.
    ofs_plat_prim_burstcount0_mapping_gearbox
      #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .SOURCE_BURST_WIDTH(SOURCE_BURST_WIDTH),
        .SINK_BURST_WIDTH(SINK_BURST_WIDTH),
        .NATURAL_ALIGNMENT(NATURAL_ALIGNMENT),
        // Map page size to lines
        .PAGE_SIZE(PAGE_SIZE >> ADDR_START)
        )
       wr_gearbox
        (
         .clk,
         .reset_n,

         .m_new_req(wr_next && mem_source.awvalid),
         .m_addr(mem_source.aw.addr[ADDR_START +: ADDR_WIDTH]),
         .m_burstcount(mem_source.aw.len),

         .s_accept_req(mem_sink.awvalid && mem_sink.awready),
         .s_req_complete(wr_complete),
         .s_addr(s_wr_address),
         .s_burstcount(s_wr_burstcount)
         );

    always_comb
    begin
        // Use field-by-field copy since data widths may be different
        `OFS_PLAT_AXI_MEM_IF_COPY_AW(mem_sink.aw, =, mem_source_reg.aw);

        mem_sink.aw.addr[ADDR_START +: ADDR_WIDTH] = s_wr_address;
        mem_sink.aw.len = s_wr_burstcount;

        // Set a bit in aw.user to indicate whether a write
        // request is from the source (and should get a response) or
        // generated here and the response should be squashed.
        mem_sink.aw.user[UFLAG_NO_REPLY] = !wr_complete || mem_source_reg.aw.user[UFLAG_NO_REPLY];
    end

    // Register write request state coming from the source that isn't held
    // in the burst count mapping gearbox.
    always_ff @(posedge clk)
    begin
        if (wr_next)
        begin
            // New request -- the last one is complete
            mem_sink.awvalid <= mem_source.awvalid;
            mem_source_reg.aw <= mem_source.aw;
        end

        if (!reset_n)
        begin
            mem_sink.awvalid <= 1'b0;
        end
    end

    // Write data
    assign mem_source.wready = mem_sink.wready;

    always_ff @(posedge clk)
    begin
        if (mem_sink.wready)
        begin
            mem_sink.wvalid <= mem_source.wvalid;
            // Field-by-field copy (sizes changed)
            `OFS_PLAT_AXI_MEM_IF_COPY_W(mem_sink.w, <=, mem_source.w);
        end

        if (!reset_n)
        begin
            mem_sink.wvalid <= 1'b0;
        end
    end

    // Write responses
    assign mem_sink.bready = mem_source.bready;

    always_ff @(posedge clk)
    begin
        if (mem_source.bready)
        begin
            // Don't forward bursts generated here
            mem_source.bvalid <= mem_sink.bvalid &&
                                 !mem_sink.b.user[UFLAG_NO_REPLY];

            // Field-by-field copy (sizes changed)
            `OFS_PLAT_AXI_MEM_IF_COPY_B(mem_source.b, <=, mem_sink.b);
        end

        if (!reset_n)
        begin
            mem_source.bvalid <= 1'b0;
        end
    end

    // synthesis translate_off

    //
    // Validated in simulation: confirm that the sink is properly
    // returning USER bits.
    //
    // The test here is simple: if there are more responses than
    // requests from the source then something is wrong.
    //
    int m_num_writes, m_num_write_responses;
    int m_num_reads, m_num_read_responses;

    always_ff @(posedge clk)
    begin
        if (m_num_read_responses > m_num_reads)
        begin
            $fatal(2, "** ERROR ** %m: More read responses than read requests! Is the sink returning b.user?");
        end

        if (mem_source.arvalid && mem_source.arready)
        begin
            m_num_reads <= m_num_reads + 1;
        end

        if (mem_source.rvalid && mem_source.rready && mem_source.r.last)
        begin
            m_num_read_responses <= m_num_read_responses + 1;
        end

        if (m_num_write_responses > m_num_writes)
        begin
            $fatal(2, "** ERROR ** %m: More write responses than write requests! Is the sink returning b.user?");
        end

        if (mem_source.awvalid && mem_source.awready)
        begin
            m_num_writes <= m_num_writes + 1;
        end

        if (mem_source.bvalid && mem_source.bready)
        begin
            m_num_write_responses <= m_num_write_responses + 1;
        end

        if (!reset_n)
        begin
            m_num_reads <= 0;
            m_num_read_responses <= 0;
            m_num_writes <= 0;
            m_num_write_responses <= 0;
        end
    end

    // synthesis translate_on

endmodule // ofs_plat_axi_mem_if_map_bursts
