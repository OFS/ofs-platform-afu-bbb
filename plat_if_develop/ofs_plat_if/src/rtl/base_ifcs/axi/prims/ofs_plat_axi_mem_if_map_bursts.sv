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
// mem_master and mem_slave may differ only in the width of their burst counts.
// Map bursts requested by the master into legal bursts in the slave.
//
module ofs_plat_axi_mem_if_map_bursts
  #(
    // Set to non-zero if addresses in the slave must be naturally aligned to
    // the burst size.
    parameter NATURAL_ALIGNMENT = 0
    )
   (
    ofs_plat_axi_mem_if.to_master mem_master,
    ofs_plat_axi_mem_if.to_slave mem_slave,

    // Write responses returned to mem_master must match the master's write burst
    // count and not the slave's. This is NOT handled inside the module here.
    // Instead, the parent module is expected to record which slave bursts get
    // responses and which don't. We do this because some parents can record
    // burst requirements as existing metadata along with requests (e.g. in CCI-P
    // mdata), thus using very few FPGA resources.
    //
    // wr_slave_burst_expects_response is set on SOP of a mem_slave.wr_write if
    // the burst requires a write response.
    output logic wr_slave_burst_expects_response
    );


    initial
    begin
        if (mem_master.ADDR_WIDTH_ != mem_slave.ADDR_WIDTH_)
            $fatal(2, "** ERROR ** %m: ADDR_WIDTH mismatch!");
        if (mem_master.DATA_WIDTH_ != mem_slave.DATA_WIDTH_)
            $fatal(2, "** ERROR ** %m: DATA_WIDTH mismatch!");
    end

    logic clk;
    assign clk = mem_slave.clk;
    logic reset_n;
    assign reset_n = mem_slave.reset_n;

    localparam ADDR_WIDTH = mem_master.ADDR_WIDTH_;
    localparam DATA_WIDTH = mem_master.DATA_WIDTH_;

    localparam MASTER_BURST_WIDTH = mem_master.BURST_CNT_WIDTH_;
    localparam SLAVE_BURST_WIDTH = mem_slave.BURST_CNT_WIDTH_;
    typedef logic [MASTER_BURST_WIDTH-1 : 0] t_master_burst_cnt;

    generate
        if ((! NATURAL_ALIGNMENT && (SLAVE_BURST_WIDTH >= MASTER_BURST_WIDTH)) ||
            (MASTER_BURST_WIDTH == 1))
        begin : nb
            // There is no alignment requirement and slave can handle all
            // master burst sizes. Just wire the two interfaces together.
            ofs_plat_axi_mem_if_connect
              simple_conn
               (
                .mem_master,
                .mem_slave
                );

            assign wr_slave_burst_expects_response = 1'b1;
        end
        else
        begin : b
            //
            // Reads
            //

            logic rd_complete;
            logic rd_next;
            assign mem_master.arready = rd_next;

            logic [mem_slave.T_AR_WIDTH-1 : 0] mem_slave_ar;
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
                .NATURAL_ALIGNMENT(NATURAL_ALIGNMENT)
                )
               rd_gearbox
                (
                 .clk,
                 .reset_n,

                 .m_new_req(rd_next),
                 .m_addr(mem_master.ar.addr),
                 .m_burstcount(mem_master.ar.len),

                 .s_accept_req(mem_slave.arready),
                 .s_req_complete(rd_complete),
                 .s_addr(s_rd_address),
                 .s_burstcount(s_rd_burstcount)
                 );

            always_comb
            begin
                mem_slave.ar = mem_slave_ar;
                mem_slave.ar.addr = s_rd_address;
                mem_slave.ar.len = s_rd_burstcount;
            end

            // Register read request state coming from the master that isn't held
            // in the burst count mapping gearbox.
            always_ff @(posedge clk)
            begin
                if (rd_next)
                begin
                    // New request -- the last one is complete
                    mem_slave.arvalid <= mem_master.arvalid;
                    mem_slave_ar <= mem_master.ar;
                end

                if (!reset_n)
                begin
                    mem_slave.arvalid <= 1'b0;
                end
            end

            // Responses don't encode anything about bursts. Forward them unmodified.
            ofs_plat_prim_ready_enable_reg
              #(
                .N_DATA_BITS(mem_master.T_R_WIDTH)
                )
              rd_rsp
               (
                .clk,
                .reset_n,
                .enable_from_src(mem_slave.rvalid),
                .data_from_src(mem_slave.r),
                .ready_to_src(mem_slave.rready),
                .enable_to_dst(mem_master.rvalid),
                .data_to_dst(mem_master.r),
                .ready_from_dst(mem_master.rready)
                );


            //
            // Writes
            //

            logic wr_complete;
            assign mem_master.awready = mem_slave.awready;

            logic [ADDR_WIDTH-1 : 0] s_wr_address;
            logic [SLAVE_BURST_WIDTH-1 : 0] s_wr_burstcount;
            logic m_wr_sop, s_wr_sop;

            // Map burst counts in the master to one or more bursts in the slave.
            ofs_plat_prim_burstcount0_mapping_gearbox
              #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .MASTER_BURST_WIDTH(MASTER_BURST_WIDTH),
                .SLAVE_BURST_WIDTH(SLAVE_BURST_WIDTH),
                .NATURAL_ALIGNMENT(NATURAL_ALIGNMENT)
                )
               wr_gearbox
                (
                 .clk,
                 .reset_n,

                 .m_new_req(mem_master.awvalid && mem_slave.awready && m_wr_sop),
                 .m_addr(mem_master.aw.addr),
                 .m_burstcount(mem_master.aw.len),

                 .s_accept_req(mem_slave.awvalid && mem_slave.awready && s_wr_sop),
                 .s_req_complete(wr_complete),
                 .s_addr(s_wr_address),
                 .s_burstcount(s_wr_burstcount)
                 );

            // Address and burstcount are valid only during the slave's SOP cycle.
            // Force 'x for debugging. (Without 'x the address and burstcount are
            // associated with the next packet, which is confusing.)
            logic [mem_slave.T_AW_WIDTH-1 : 0] mem_slave_aw;

            always_comb
            begin
                mem_slave.aw = mem_slave_aw;
                mem_slave.aw.addr = s_wr_sop ? s_wr_address : 'x;
                mem_slave.aw.len = s_wr_sop ? s_wr_burstcount : 'x;
            end

            // Register write request state coming from the master that isn't held
            // in the burst count mapping gearbox.
            always_ff @(posedge clk)
            begin
                if (mem_slave.awready)
                begin
                    // New request -- the last one is complete
                    mem_slave.awvalid <= mem_master.awvalid;
                    mem_slave_aw <= mem_master.aw;
                end

                if (!reset_n)
                begin
                    mem_slave.awvalid <= 1'b0;
                end
            end

            // Write ACKs can flow back unchanged. It is up to the part of this
            // module to ensure that there is only one write ACK per master burst.
            // The output port wr_slave_burst_expects_response can be used by the
            // parent module for this purpose.
            assign wr_slave_burst_expects_response = wr_complete && s_wr_sop;

            // Write data
            ofs_plat_prim_ready_enable_reg
              #(
                .N_DATA_BITS(mem_master.T_W_WIDTH)
                )
              wr_data
               (
                .clk,
                .reset_n,
                .enable_from_src(mem_master.wvalid),
                .data_from_src(mem_master.w),
                .ready_to_src(mem_master.wready),
                .enable_to_dst(mem_slave.wvalid),
                .data_to_dst(mem_slave.w),
                .ready_from_dst(mem_slave.wready)
                );

            // Write responses
            ofs_plat_prim_ready_enable_reg
              #(
                .N_DATA_BITS(mem_master.T_B_WIDTH)
                )
              wr_rsp
               (
                .clk,
                .reset_n,
                .enable_from_src(mem_slave.bvalid),
                .data_from_src(mem_slave.b),
                .ready_to_src(mem_slave.bready),
                .enable_to_dst(mem_master.bvalid),
                .data_to_dst(mem_master.b),
                .ready_from_dst(mem_master.bready)
                );

            ofs_plat_prim_burstcount0_sop_tracker
              #(
                .BURST_CNT_WIDTH(MASTER_BURST_WIDTH)
                )
              m_sop_tracker
               (
                .clk,
                .reset_n,
                .flit_valid(mem_master.awvalid && mem_master.awready),
                .burstcount(mem_master.aw.len),
                .sop(m_wr_sop),
                .eop()
                );

            ofs_plat_prim_burstcount0_sop_tracker
              #(
                .BURST_CNT_WIDTH(SLAVE_BURST_WIDTH)
                )
              s_sop_tracker
               (
                .clk,
                .reset_n,
                .flit_valid(mem_slave.awvalid && mem_slave.awready),
                .burstcount(mem_slave.aw.len),
                .sop(s_wr_sop),
                .eop()
                );

            // synthesis translate_off

            //
            // Validated in simulation: confirm that the parent module is properly
            // gating write responses based on wr_slave_burst_expects_response.
            // The test here is simple: if there are more write responses than
            // write requests from the master then something is wrong.
            //
            int m_num_writes, m_num_write_responses;

            always_ff @(posedge clk)
            begin
                if (m_num_write_responses > m_num_writes)
                begin
                    $fatal(2, "** ERROR ** %m: More write responses than write requests! Is the parent module honoring wr_slave_burst_expects_response?");
                end

                if (mem_master.awvalid && mem_master.awready && m_wr_sop)
                begin
                    m_num_writes <= m_num_writes + 1;
                end

                if (mem_slave.bvalid && mem_slave.bready)
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

endmodule // ofs_plat_axi_mem_if_map_bursts
