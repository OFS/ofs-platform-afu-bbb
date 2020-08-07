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
// Map bursts requested by the master into legal bursts in the slave.
//
module ofs_plat_axi_mem_if_map_bursts
  #(
    // Which bit in the mem_slave user flags should be set to indicate
    // injected bursts that should be dropped so that the AFU sees
    // only responses to its original bursts?
    parameter UFLAG_NO_REPLY = 0,

    // Set to non-zero if addresses in the slave must be naturally aligned to
    // the burst size.
    parameter NATURAL_ALIGNMENT = 0,

    // Set to a page size if the slave must avoid bursts that cross pages.
    parameter PAGE_SIZE = 0
    )
   (
    ofs_plat_axi_mem_if.to_master mem_master,
    ofs_plat_axi_mem_if.to_slave mem_slave
    );

    logic clk;
    assign clk = mem_slave.clk;
    logic reset_n;
    assign reset_n = mem_slave.reset_n;

    localparam MASTER_BURST_WIDTH = mem_master.BURST_CNT_WIDTH_;
    localparam SLAVE_BURST_WIDTH = mem_slave.BURST_CNT_WIDTH_;

    generate
        if ((!NATURAL_ALIGNMENT && !PAGE_SIZE && (SLAVE_BURST_WIDTH >= MASTER_BURST_WIDTH)) ||
            (MASTER_BURST_WIDTH == 1))
        begin : nb
            // There is no alignment requirement and slave can handle all
            // master burst sizes. Just wire the two interfaces together.
            ofs_plat_axi_mem_if_connect_by_field
              simple_conn
               (
                .mem_master,
                .mem_slave
                );
        end
        else
        begin : b
            ofs_plat_axi_mem_if
              #(
                `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_slave)
                )
              slave_burst_if();

            assign slave_burst_if.clk = mem_slave.clk;
            assign slave_burst_if.reset_n = mem_slave.reset_n;
            assign slave_burst_if.instance_number = mem_slave.instance_number;

            ofs_plat_axi_mem_if_map_bursts_impl
              #(
                .UFLAG_NO_REPLY(UFLAG_NO_REPLY),
                .NATURAL_ALIGNMENT(NATURAL_ALIGNMENT),
                .PAGE_SIZE(PAGE_SIZE)
                )
              mapper
               (
                .mem_master,
                .mem_slave(slave_burst_if)
                );

            // When bursts are broken up the last flag on write data needs
            // to be set at the end of new packets.
            ofs_plat_axi_mem_if_fixup_wlast
              fixup_wlast
               (
                .mem_master(slave_burst_if),
                .mem_slave
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
    // Which bit in the mem_slave user flags should be set to indicate
    // injected bursts that should be dropped so that the AFU sees
    // only responses to its original bursts?
    parameter UFLAG_NO_REPLY = 0,

    // Set to non-zero if addresses in the slave must be naturally aligned to
    // the burst size.
    parameter NATURAL_ALIGNMENT = 0,

    // Set to a page size if the slave must avoid bursts that cross pages.
    parameter PAGE_SIZE = 0
    )
   (
    ofs_plat_axi_mem_if.to_master mem_master,
    ofs_plat_axi_mem_if.to_slave mem_slave
    );

    logic clk;
    assign clk = mem_slave.clk;
    logic reset_n;
    assign reset_n = mem_slave.reset_n;

    // We only care about the address portion that is the line index
    localparam ADDR_WIDTH = mem_master.ADDR_LINE_IDX_WIDTH;
    localparam ADDR_START = mem_master.ADDR_BYTE_IDX_WIDTH;
    localparam DATA_WIDTH = mem_master.DATA_WIDTH_;

    localparam MASTER_BURST_WIDTH = mem_master.BURST_CNT_WIDTH_;
    localparam SLAVE_BURST_WIDTH = mem_slave.BURST_CNT_WIDTH_;
    typedef logic [MASTER_BURST_WIDTH-1 : 0] t_master_burst_cnt;

    // Instantiate an interface to use the properly sized internal structs
    // as registers.
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_master),
        .DISABLE_CHECKER(1)
        )
        mem_master_reg();

    //
    // Reads
    //

    logic rd_complete;
    logic rd_next;
    assign mem_master.arready = rd_next;

    logic [ADDR_WIDTH-1 : 0] s_rd_address;
    logic [SLAVE_BURST_WIDTH-1 : 0] s_rd_burstcount;

    // Ready to start a new read request coming from the master? Yes if
    // there is no current request or the previous one is complete.
    assign rd_next = mem_slave.arready && (!mem_slave.arvalid || rd_complete);

    // Map burst counts in the master to one or more bursts in the slave.
    ofs_plat_prim_burstcount0_mapping_gearbox
      #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .MASTER_BURST_WIDTH(MASTER_BURST_WIDTH),
        .SLAVE_BURST_WIDTH(SLAVE_BURST_WIDTH),
        .NATURAL_ALIGNMENT(NATURAL_ALIGNMENT),
        .PAGE_SIZE(PAGE_SIZE)
        )
       rd_gearbox
        (
         .clk,
         .reset_n,

         .m_new_req(rd_next && mem_master.arvalid),
         .m_addr(mem_master.ar.addr[ADDR_START +: ADDR_WIDTH]),
         .m_burstcount(mem_master.ar.len),

         .s_accept_req(mem_slave.arvalid && mem_slave.arready),
         .s_req_complete(rd_complete),
         .s_addr(s_rd_address),
         .s_burstcount(s_rd_burstcount)
         );

    always_comb
    begin
        // Use field-by-field copy since data widths may be different
        `OFS_PLAT_AXI_MEM_IF_COPY_AR(mem_slave.ar, =, mem_master_reg.ar);

        mem_slave.ar.addr[ADDR_START +: ADDR_WIDTH] = s_rd_address;
        mem_slave.ar.len = s_rd_burstcount;

        // Set a bit in ar.user to indicate whether a read
        // request is from the master (and thus completes a master
        // read request) or is generated here and should not get an
        // r.last tag.
        mem_slave.ar.user[UFLAG_NO_REPLY] = !rd_complete;
    end

    // Register read request state coming from the master that isn't held
    // in the burst count mapping gearbox.
    always_ff @(posedge clk)
    begin
        if (rd_next)
        begin
            // New request -- the last one is complete
            mem_slave.arvalid <= mem_master.arvalid;
            mem_master_reg.ar <= mem_master.ar;
        end

        if (!reset_n)
        begin
            mem_slave.arvalid <= 1'b0;
        end
    end

    // Read responses
    assign mem_slave.rready = mem_master.rready;

    always_ff @(posedge clk)
    begin
        if (mem_master.rready)
        begin
            mem_master.rvalid <= mem_slave.rvalid;

            // Use field-by-field copy since data widths may be different
            `OFS_PLAT_AXI_MEM_IF_COPY_R(mem_master.r, <=, mem_slave.r);

            // Don't mark end of burst unless it corresponds to a master burst
            mem_master.r.last <= mem_slave.r.last &&
                                 !mem_slave.r.user[UFLAG_NO_REPLY];
        end

        if (!reset_n)
        begin
            mem_master.rvalid <= 1'b0;
        end
    end


    //
    // Writes
    //

    logic wr_complete;
    logic wr_next;
    assign mem_master.awready = wr_next;

    logic [ADDR_WIDTH-1 : 0] s_wr_address;
    logic [SLAVE_BURST_WIDTH-1 : 0] s_wr_burstcount;

    // Ready to start a new write request coming from the master? Yes if
    // there is no current request or the previous one is complete.
    assign wr_next = mem_slave.awready && (!mem_slave.awvalid || wr_complete);

    // Map burst counts in the master to one or more bursts in the slave.
    ofs_plat_prim_burstcount0_mapping_gearbox
      #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .MASTER_BURST_WIDTH(MASTER_BURST_WIDTH),
        .SLAVE_BURST_WIDTH(SLAVE_BURST_WIDTH),
        .NATURAL_ALIGNMENT(NATURAL_ALIGNMENT),
        .PAGE_SIZE(PAGE_SIZE)
        )
       wr_gearbox
        (
         .clk,
         .reset_n,

         .m_new_req(wr_next && mem_master.awvalid),
         .m_addr(mem_master.aw.addr[ADDR_START +: ADDR_WIDTH]),
         .m_burstcount(mem_master.aw.len),

         .s_accept_req(mem_slave.awvalid && mem_slave.awready),
         .s_req_complete(wr_complete),
         .s_addr(s_wr_address),
         .s_burstcount(s_wr_burstcount)
         );

    always_comb
    begin
        // Use field-by-field copy since data widths may be different
        `OFS_PLAT_AXI_MEM_IF_COPY_AW(mem_slave.aw, =, mem_master_reg.aw);

        mem_slave.aw.addr[ADDR_START +: ADDR_WIDTH] = s_wr_address;
        mem_slave.aw.len = s_wr_burstcount;

        // Set a bit in aw.user to indicate whether a write
        // request is from the master (and should get a response) or
        // generated here and the response should be squashed.
        mem_slave.aw.user[UFLAG_NO_REPLY] = !wr_complete;
    end

    // Register write request state coming from the master that isn't held
    // in the burst count mapping gearbox.
    always_ff @(posedge clk)
    begin
        if (wr_next)
        begin
            // New request -- the last one is complete
            mem_slave.awvalid <= mem_master.awvalid;
            mem_master_reg.aw <= mem_master.aw;
        end

        if (!reset_n)
        begin
            mem_slave.awvalid <= 1'b0;
        end
    end

    // Write data
    assign mem_master.wready = mem_slave.wready;

    always_ff @(posedge clk)
    begin
        if (mem_slave.wready)
        begin
            mem_slave.wvalid <= mem_master.wvalid;
            // Field-by-field copy (sizes changed)
            `OFS_PLAT_AXI_MEM_IF_COPY_W(mem_slave.w, <=, mem_master.w);
        end

        if (!reset_n)
        begin
            mem_slave.wvalid <= 1'b0;
        end
    end

    // Write responses
    assign mem_slave.bready = mem_master.bready;

    always_ff @(posedge clk)
    begin
        if (mem_master.bready)
        begin
            // Don't forward bursts generated here
            mem_master.bvalid <= mem_slave.bvalid &&
                                 !mem_slave.b.user[UFLAG_NO_REPLY];

            // Field-by-field copy (sizes changed)
            `OFS_PLAT_AXI_MEM_IF_COPY_B(mem_master.b, <=, mem_slave.b);
        end

        if (!reset_n)
        begin
            mem_master.bvalid <= 1'b0;
        end
    end

    // synthesis translate_off

    //
    // Validated in simulation: confirm that the slave is properly
    // returning USER bits.
    //
    // The test here is simple: if there are more responses than
    // requests from the master then something is wrong.
    //
    int m_num_writes, m_num_write_responses;
    int m_num_reads, m_num_read_responses;

    always_ff @(posedge clk)
    begin
        if (m_num_read_responses > m_num_reads)
        begin
            $fatal(2, "** ERROR ** %m: More read responses than read requests! Is the slave returning b.user?");
        end

        if (mem_master.arvalid && mem_master.arready)
        begin
            m_num_reads <= m_num_reads + 1;
        end

        if (mem_master.rvalid && mem_master.rready && mem_master.r.last)
        begin
            m_num_read_responses <= m_num_read_responses + 1;
        end

        if (m_num_write_responses > m_num_writes)
        begin
            $fatal(2, "** ERROR ** %m: More write responses than write requests! Is the slave returning b.user?");
        end

        if (mem_master.awvalid && mem_master.awready)
        begin
            m_num_writes <= m_num_writes + 1;
        end

        if (mem_master.bvalid && mem_master.bready)
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
