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
// Service multiple CCI-P AFU interfaces with a single FIU interface. The
// most common use of this module in the PIM is for testing: simulating
// platforms with multiple CCI-P host channels on platforms with only a
// single host interface. Developers are free to use it for other purposes.
//
// In this implementation only to_afu[0] handles MMIO reads and writes.
// Other channels see no MMIO traffic.
//
// *** WARNING ***
//
//   High bits of incoming AFU Tx header mdata must be zero.
//   $clog2(NUM_AFU_PORTS) high mdata bits are used to route FIU responses
//   back to the proper AFU. It is up to the AFU to guarantee these bits
//   are zero. They will be overwritten here and reset to 0 in responses.
//
// *** WARNING ***
//

`include "ofs_plat_if.vh"

module ofs_plat_shim_ccip_mux
  #(
    parameter NUM_AFU_PORTS = 2,

    // Extra stages to add to usual almost full threshold
    parameter THRESHOLD_EXTRA = 6
    )
   (
    // Connection toward the FIU
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    // Connection toward the AFU
    ofs_plat_host_ccip_if.to_afu to_afu[NUM_AFU_PORTS]
    );

    import ofs_plat_ccip_if_funcs_pkg::*;

    wire clk;
    assign clk = to_fiu.clk;

    genvar p;
    generate
        for (p = 0; p < NUM_AFU_PORTS; p = p + 1)
        begin : r
            assign to_afu[p].clk = to_fiu.clk;
            assign to_afu[p].reset = to_fiu.reset;
            assign to_afu[p].error = to_fiu.error;
            assign to_afu[p].instance_number = to_fiu.instance_number + p;
        end
    endgenerate

    logic reset = 1'b1;
    always @(posedge clk)
    begin
        reset <= to_fiu.reset;
    end

    //
    // The MUX will store the port index of a request in the mdata field's
    // high bits.
    //
    typedef logic [$clog2(NUM_AFU_PORTS)-1 : 0] t_port_idx;
    localparam MDATA_IDX_HIGH = CCIP_MDATA_WIDTH - 1;
    localparam MDATA_IDX_LOW = CCIP_MDATA_WIDTH - $bits(t_port_idx);


    // ====================================================================
    //
    //  Channel 0 (read)
    //
    // ====================================================================

    generate
        if (NUM_AFU_PORTS < 2)
        begin : c0_nm
            //
            // No MUX required with only one AFU CCI-P port
            //

            assign to_fiu.sTx.c0 = to_afu[0].sTx.c0;

            assign to_afu[0].sRx.c0TxAlmFull = to_fiu.sRx.c0TxAlmFull;
            assign to_afu[0].sRx.c0 = to_fiu.sRx.c0;
        end
        else
        begin : c0_m
            //
            // Queue requests from AFUs in FIFOs.
            //
            t_if_ccip_c0_Tx afu_c0Tx[NUM_AFU_PORTS];
            logic [NUM_AFU_PORTS-1 : 0] afu_c0Tx_notEmpty;
            logic [NUM_AFU_PORTS-1 : 0] afu_c0Tx_deq_en;

            for (p = 0; p < NUM_AFU_PORTS; p = p + 1)
            begin : f
                // synthesis translate_off
                always_ff @(posedge clk)
                begin
                    // High bits of incoming Tx mdata must be 0. This is where
                    // the index of the AFU will be stored so responses are
                    // routed to the correct AFU.
                    if (! reset && to_afu[p].sTx.c0.valid)
                    begin
                        assert (to_afu[p].sTx.c0.hdr.mdata[MDATA_IDX_HIGH:MDATA_IDX_LOW] ==
                                t_port_idx'(0)) else
                            $fatal(2, "** ERROR ** %m: Non-zero AFU %0d c0Tx mdata high bits", p);
                    end
                end
                // synthesis translate_on

                ofs_plat_prim_fifo_lutram
                  #(
                    .N_DATA_BITS($bits(t_if_ccip_c0_Tx)),
                    .N_ENTRIES(CCIP_TX_ALMOST_FULL_THRESHOLD + 4),
                    .THRESHOLD(CCIP_TX_ALMOST_FULL_THRESHOLD),
                    .REGISTER_OUTPUT(1)
                    )
                  fifo_in
                   (
                    .clk,
                    .reset,
                    .enq_data(to_afu[p].sTx.c0),
                    .enq_en(to_afu[p].sTx.c0.valid),
                    .notFull(),
                    .almostFull(to_afu[p].sRx.c0TxAlmFull),
                    .first(afu_c0Tx[p]),
                    .deq_en(afu_c0Tx_deq_en[p]),
                    .notEmpty(afu_c0Tx_notEmpty[p])
                    );
            end


            //
            // Round-robin arbitration to pick a request from among the
            // active AFUs.
            //
            t_port_idx afu_c0Tx_grantIdx;

            ofs_plat_prim_arb_rr
              #(
                .NUM_CLIENTS(NUM_AFU_PORTS)
                )
              arb
               (
                .clk,
                .reset,
                .ena(! to_fiu.sRx.c0TxAlmFull),
                .request(afu_c0Tx_notEmpty),
                .grant(afu_c0Tx_deq_en),
                .grantIdx(afu_c0Tx_grantIdx)
                );


            t_if_ccip_c0_Tx fiu_c0Tx;

            always_ff @(posedge clk)
            begin
                // Forward arbitration winner. One of the deq_en bits will be
                // high only if a request is available and the FIU isn't full.
                fiu_c0Tx <= afu_c0Tx[afu_c0Tx_grantIdx];
                fiu_c0Tx.hdr.mdata[MDATA_IDX_HIGH:MDATA_IDX_LOW] <= afu_c0Tx_grantIdx;
                fiu_c0Tx.valid <= (|(afu_c0Tx_deq_en));

                to_fiu.sTx.c0 <= fiu_c0Tx;

                if (reset)
                begin
                    to_fiu.sTx.c0.valid <= 1'b0;
                end
            end

            //
            // Forward responses to the proper AFU. Fan out the response
            // everywhere but manage the valid bits so the response goes
            // to the right AFU.
            //
            for (p = 0; p < NUM_AFU_PORTS; p = p + 1)
            begin
                always_ff @(posedge clk)
                begin
                    to_afu[p].sRx.c0 <= to_fiu.sRx.c0;
                    if (to_fiu.sRx.c0.rspValid)
                    begin
                        to_afu[p].sRx.c0.hdr.mdata[MDATA_IDX_HIGH:MDATA_IDX_LOW] <= t_port_idx'(0);
                    end

                    to_afu[p].sRx.c0.rspValid <=
                        to_fiu.sRx.c0.rspValid &&
                        (t_port_idx'(p) == to_fiu.sRx.c0.hdr.mdata[MDATA_IDX_HIGH:MDATA_IDX_LOW]);

                    // MMIO requests go only to AFU 0
                    if (p != 0)
                    begin
                        to_afu[p].sRx.c0.mmioRdValid <= 1'b0;
                        to_afu[p].sRx.c0.mmioWrValid <= 1'b0;
                    end
                end
            end
        end
    endgenerate


    // ====================================================================
    //
    //  Channel 1 (write) flows straight through.
    //
    // ====================================================================

    generate
        if (NUM_AFU_PORTS < 2)
        begin : c1_nm
            //
            // No MUX required with only one AFU CCI-P port
            //

            assign to_fiu.sTx.c1 = to_afu[0].sTx.c1;

            assign to_afu[0].sRx.c1TxAlmFull = to_fiu.sRx.c1TxAlmFull;
            assign to_afu[0].sRx.c1 = to_fiu.sRx.c1;
        end
        else
        begin : c1_m
            //
            // Queue requests from AFUs in FIFOs.
            //
            t_if_ccip_c1_Tx afu_c1Tx[NUM_AFU_PORTS];
            logic [NUM_AFU_PORTS-1 : 0] afu_c1Tx_notEmpty;
            logic [NUM_AFU_PORTS-1 : 0] afu_c1Tx_deq_en;
            logic [NUM_AFU_PORTS-1 : 0] afu_c1Tx_is_eop;

            for (p = 0; p < NUM_AFU_PORTS; p = p + 1)
            begin : f
                // synthesis translate_off
                always_ff @(posedge clk)
                begin
                    // High bits of incoming Tx mdata must be 0. This is where
                    // the index of the AFU will be stored so responses are
                    // routed to the correct AFU.
                    if (! reset && to_afu[p].sTx.c1.valid)
                    begin
                        assert (to_afu[p].sTx.c1.hdr.mdata[MDATA_IDX_HIGH:MDATA_IDX_LOW] ==
                                t_port_idx'(0)) else
                            $fatal(2, "** ERROR ** %m: Non-zero AFU %0d c1Tx mdata high bits", p);

                        // Interrupts only allowed on AFU 0 since we have no way to
                        // route responses.
                        assert ((p == 0) || (to_afu[p].sTx.c1.hdr.req_type != eREQ_INTR)) else
                            $fatal(2, "** ERROR ** %m: AFU %0d c1Tx may not request interrupts", p);
                    end
                end
                // synthesis translate_on

                //
                // Generate an end-of-packet bit for each AFUs write request stream.
                // Arbitration must keep multi-line writes contiguous.
                //
                logic is_eop;

                ofs_plat_utils_ccip_track_multi_write track_eop
                   (
                    .clk,
                    .reset,
                    .c1Tx(to_afu[p].sTx.c1),
                    .c1Tx_en(1'b1),
                    .eop(is_eop),
                    .packetActive(),
                    .nextBeatNum()
                    );

                ofs_plat_prim_fifo_lutram
                  #(
                    .N_DATA_BITS(1 + $bits(t_if_ccip_c1_Tx)),
                    .N_ENTRIES(CCIP_TX_ALMOST_FULL_THRESHOLD + 4),
                    .THRESHOLD(CCIP_TX_ALMOST_FULL_THRESHOLD),
                    .REGISTER_OUTPUT(1)
                    )
                  fifo_in
                   (
                    .clk,
                    .reset,
                    .enq_data({ is_eop, to_afu[p].sTx.c1 }),
                    .enq_en(to_afu[p].sTx.c1.valid),
                    .notFull(),
                    .almostFull(to_afu[p].sRx.c1TxAlmFull),
                    .first({ afu_c1Tx_is_eop[p], afu_c1Tx[p] }),
                    .deq_en(afu_c1Tx_deq_en[p]),
                    .notEmpty(afu_c1Tx_notEmpty[p])
                    );
            end


            //
            // Round-robin arbitration to pick a request from among the
            // active AFUs.
            //
            logic [NUM_AFU_PORTS-1 : 0] arb_grant;
            t_port_idx arb_grantIdx;
            logic is_sop;

            ofs_plat_prim_arb_rr
              #(
                .NUM_CLIENTS(NUM_AFU_PORTS)
                )
              arb
               (
                .clk,
                .reset,
                .ena(is_sop && ! to_fiu.sRx.c1TxAlmFull),
                .request(afu_c1Tx_notEmpty),
                .grant(arb_grant),
                .grantIdx(arb_grantIdx)
                );


            //
            // Grants are sticky for multi-line writes. Record the grant winner
            // when arbitration is enabled. Multi-line writes hold the grant for
            // a full multi-beat packet.
            t_port_idx afu_c1Tx_grantIdx, afu_c1Tx_grantIdx_q;

            always_comb
            begin
                if (is_sop)
                begin
                    // Start of a new request -- use the arbiter
                    afu_c1Tx_grantIdx = arb_grantIdx;
                    afu_c1Tx_deq_en = arb_grant;
                end
                else
                begin
                    // Hold arbitration while the multi-beat packet completes
                    afu_c1Tx_grantIdx = afu_c1Tx_grantIdx_q;
                    afu_c1Tx_deq_en = '0;
                    afu_c1Tx_deq_en[afu_c1Tx_grantIdx_q] = afu_c1Tx_notEmpty[afu_c1Tx_grantIdx_q];
                end
            end

            always_ff @(posedge clk)
            begin
                afu_c1Tx_grantIdx_q <= afu_c1Tx_grantIdx;
            end


            t_if_ccip_c1_Tx fiu_c1Tx;

            always_ff @(posedge clk)
            begin
                // Forward arbitration winner. One of the deq_en bits will be
                // high only if a request is available and the FIU isn't full.
                fiu_c1Tx <= afu_c1Tx[afu_c1Tx_grantIdx];
                fiu_c1Tx.hdr.mdata[MDATA_IDX_HIGH:MDATA_IDX_LOW] <= afu_c1Tx_grantIdx;
                fiu_c1Tx.valid <= (|(afu_c1Tx_deq_en));

                if (|(afu_c1Tx_deq_en))
                begin
                    is_sop <= afu_c1Tx_is_eop[afu_c1Tx_grantIdx];
                end

                to_fiu.sTx.c1 <= fiu_c1Tx;

                if (reset)
                begin
                    is_sop <= 1'b1;
                    to_fiu.sTx.c1.valid <= 1'b0;
                end
            end

            //
            // Forward responses to the proper AFU. Fan out the response
            // everywhere but manage the valid bits so the response goes
            // to the right AFU.
            //
            for (p = 0; p < NUM_AFU_PORTS; p = p + 1)
            begin
                always_ff @(posedge clk)
                begin
                    to_afu[p].sRx.c1 <= to_fiu.sRx.c1;
                    if (to_fiu.sRx.c1.hdr.resp_type != eRSP_INTR)
                    begin
                        to_afu[p].sRx.c1.hdr.mdata[MDATA_IDX_HIGH:MDATA_IDX_LOW] <= t_port_idx'(0);
                    end

                    to_afu[p].sRx.c1.rspValid <= 1'b0;
                    if (to_fiu.sRx.c1.rspValid)
                    begin
                        if (to_fiu.sRx.c1.hdr.resp_type == eRSP_INTR)
                        begin
                            // Interrupts only allowed from port 0.
                            to_afu[p].sRx.c1.rspValid <= (p == 0);
                        end
                        else
                        begin
                            // All other messages are routed based on mdata.
                            to_afu[p].sRx.c1.rspValid <=
                                (t_port_idx'(p) == to_fiu.sRx.c1.hdr.mdata[MDATA_IDX_HIGH:MDATA_IDX_LOW]);
                        end
                    end
                end
            end
        end
    endgenerate


    // ====================================================================
    //
    //  Channel 2 Tx (MMIO read response) flows straight through.
    //  Only index 0 supports MMIO.
    //
    // ====================================================================

    assign to_fiu.sTx.c2 = to_afu[0].sTx.c2;

endmodule // ofs_plat_shim_ccip_mux
