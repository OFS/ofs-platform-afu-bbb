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
module ofs_plat_avalon_mem_if_map_bursts
  #(
    // Set to non-zero if addresses in the slave must be naturally aligned to
    // the burst size.
    parameter NATURAL_ALIGNMENT = 0
    )
   (
    ofs_plat_avalon_mem_if.to_master mem_master,
    ofs_plat_avalon_mem_if.to_slave mem_slave,

    // Write responses returned to mem_master must match the master's write burst
    // count and not the slave's. This is NOT handled inside the module here.
    // Instead, the parent module is expected to record which slave bursts get
    // responses and which don't. We do this because some parents can record
    // burst requirements as existing metadata along with requests, thus using
    // very few FPGA resources.
    //
    // wr_slave_burst_expects_response is set on SOP of a mem_slave.write if
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
    localparam DATA_N_BYTES = mem_master.DATA_N_BYTES;

    localparam MASTER_BURST_WIDTH = mem_master.BURST_CNT_WIDTH_;
    localparam SLAVE_BURST_WIDTH = mem_slave.BURST_CNT_WIDTH_;
    typedef logic [MASTER_BURST_WIDTH-1 : 0] t_master_burst_cnt;

    generate
        if ((! NATURAL_ALIGNMENT && (SLAVE_BURST_WIDTH >= MASTER_BURST_WIDTH)) ||
            (MASTER_BURST_WIDTH == 1))
        begin : nb
            // There is no alignment requirement and slave can handle all
            // master burst sizes. Just wire the two interfaces together.
            ofs_plat_avalon_mem_if_connect
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
            // Break master bursts into slave-sized bursts.
            //
            logic req_complete;
            logic m_new_req;
            logic [ADDR_WIDTH-1 : 0] s_address;
            logic [SLAVE_BURST_WIDTH-1 : 0] s_burstcount;
            logic m_wr_sop, s_wr_sop;

            // New flits are allowed as long as the slave isn't in waitrequest
            // and the previous read is complete. Writes aren't a problem since
            // the data flit count is the same, independent of burst sizes.
            assign mem_master.waitrequest = mem_slave.waitrequest ||
                                            (mem_slave.read && ! req_complete);

            // Ready to start a new packet burst request coming from the master?
            // Only master reads or master write SOP flits start a new request.
            assign m_new_req = ! mem_master.waitrequest && m_wr_sop;

            // Slave ready to accept request? For reads, this is easy: a request
            // may be accepted as long as the slave's waitrequest is clear.
            // Writes accept requests only in the SOP beat of slave bursts.
            logic s_accept_req;
            assign s_accept_req = ! mem_slave.waitrequest && s_wr_sop &&
                                  (mem_slave.write || mem_slave.read);

            // Map burst counts in the master to one or more bursts in the slave.
            ofs_plat_prim_burstcount1_mapping_gearbox
              #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .MASTER_BURST_WIDTH(MASTER_BURST_WIDTH),
                .SLAVE_BURST_WIDTH(SLAVE_BURST_WIDTH),
                .NATURAL_ALIGNMENT(NATURAL_ALIGNMENT)
                )
               gearbox
                (
                 .clk,
                 .reset_n,

                 .m_new_req,
                 .m_addr(mem_master.address),
                 .m_burstcount(mem_master.burstcount),

                 .s_accept_req,
                 .s_req_complete(req_complete),
                 .s_addr(s_address),
                 .s_burstcount(s_burstcount)
                 );

            // Register request state coming from the master that isn't held
            // in the burst count mapping gearbox.
            always_ff @(posedge clk)
            begin
                if (! mem_master.waitrequest)
                begin
                    mem_slave.read <= mem_master.read;
                    mem_slave.write <= mem_master.write;
                    mem_slave.writedata <= mem_master.writedata;
                    mem_slave.byteenable <= mem_master.byteenable;
                end

                if (!reset_n)
                begin
                    mem_slave.read <= 1'b0;
                    mem_slave.write <= 1'b0;
                end
            end

            // Address and burstcount are valid only during the slave's SOP cycle.
            // (SOP is valid when reads arrive too, since the slave was prepared
            // to accept the SOP of a write.)
            //
            // Force 'x for debugging. (Without 'x the address and burstcount are
            // associated with the next packet, which is confusing.)
            assign mem_slave.address = s_wr_sop ? s_address : 'x;
            assign mem_slave.burstcount = s_wr_sop ? s_burstcount : 'x;

            // Responses don't encode anything about bursts. Forward them unmodified.
            assign mem_master.readdatavalid = mem_slave.readdatavalid;
            assign mem_master.readdata = mem_slave.readdata;
            assign mem_master.response = mem_slave.response;

            assign mem_master.writeresponsevalid = mem_slave.writeresponsevalid;
            assign mem_master.writeresponse = mem_slave.writeresponse;

            // Write ACKs can flow back unchanged. It is up to the part of this
            // module to ensure that there is only one write ACK per master burst.
            // The output port wr_slave_burst_expects_response can be used by the
            // parent module for this purpose.
            assign wr_slave_burst_expects_response = req_complete && s_wr_sop &&
                                                     mem_slave.write;

            //
            // Write SOP tracking
            //

            ofs_plat_prim_burstcount1_sop_tracker
              #(
                .BURST_CNT_WIDTH(MASTER_BURST_WIDTH)
                )
              m_sop_tracker
               (
                .clk,
                .reset_n,
                .flit_valid(mem_master.write && ! mem_master.waitrequest),
                .burstcount(mem_master.burstcount),
                .sop(m_wr_sop),
                .eop()
                );

            ofs_plat_prim_burstcount1_sop_tracker
              #(
                .BURST_CNT_WIDTH(SLAVE_BURST_WIDTH)
                )
              s_sop_tracker
               (
                .clk,
                .reset_n,
                .flit_valid(mem_slave.write && ! mem_slave.waitrequest),
                .burstcount(mem_slave.burstcount),
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

                if (mem_master.write && ! mem_master.waitrequest && m_wr_sop)
                begin
                    m_num_writes <= m_num_writes + 1;
                end

                if (mem_master.writeresponsevalid)
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
