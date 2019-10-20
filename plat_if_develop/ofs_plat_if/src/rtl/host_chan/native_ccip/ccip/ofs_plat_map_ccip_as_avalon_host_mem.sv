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
// Map CCI-P host memory traffic to an Avalon channel. The incoming CCI-P
// responses are assumed to be sorted already and in the same clock domain,
// making the Avalon mapping relatively easy.
//
module ofs_plat_map_ccip_as_avalon_host_mem
   (
    input  logic clk,
    input  logic reset,
    input  int unsigned instance_number,
    input  t_if_ccip_Rx sRx,
    output t_if_ccip_c0_Tx c0Tx,
    output t_if_ccip_c1_Tx c1Tx,

    ofs_plat_avalon_mem_rdwr_if.to_master_clk host_mem_to_afu
    );

    import ofs_plat_ccip_if_funcs_pkg::*;

    assign host_mem_to_afu.clk = clk;
    assign host_mem_to_afu.reset = reset;
    assign host_mem_to_afu.instance_number = instance_number;

    // Map almost full to Avalon waitrequest
    always_ff @(posedge clk)
    begin
        host_mem_to_afu.rd_waitrequest <= sRx.c0TxAlmFull;
        host_mem_to_afu.wr_waitrequest <= sRx.c1TxAlmFull;
    end

    //
    // Host memory reads
    //
    always_ff @(posedge clk)
    begin
        c0Tx.valid <= host_mem_to_afu.rd_read && ! host_mem_to_afu.rd_waitrequest;

        c0Tx.hdr <= t_ccip_c0_ReqMemHdr'(0);
        c0Tx.hdr.address <= host_mem_to_afu.rd_address;
        c0Tx.hdr.req_type <= eREQ_RDLINE_I;
        c0Tx.hdr.cl_len <= t_ccip_clLen'(host_mem_to_afu.rd_burstcount - 3'b1);

        if (reset)
        begin
            c0Tx.valid <= 1'b0;
        end
    end

    // CCI-P responses are already sorted. Just forward them to Avalon.
    always_ff @(posedge clk)
    begin
        host_mem_to_afu.rd_readdatavalid <= ccip_c0Rx_isReadRsp(sRx.c0);
        host_mem_to_afu.rd_readdata <= sRx.c0.data;

        if (reset)
        begin
            host_mem_to_afu.rd_readdatavalid <= 1'b0;
        end
    end

    assign host_mem_to_afu.rd_response = 2'b0;

    //
    // Host memory writes
    //
    logic wr_beat_valid;
    assign wr_beat_valid = host_mem_to_afu.wr_write && ! host_mem_to_afu.wr_waitrequest;

    logic wr_sop;
    t_ccip_clLen wr_cl_len;
    t_ccip_clNum wr_cl_num;

    // Is the current incoming write line the end of a packet? It is if either
    // starting a new single-line packet or all lines of a multi-line
    // package have now arrived.
    logic wr_eop;
    assign wr_eop = (wr_sop && (host_mem_to_afu.wr_burstcount == 3'b1)) ||
                    (!wr_sop && (wr_cl_num == t_ccip_clNum'(wr_cl_len)));

    always_ff @(posedge clk)
    begin
        c1Tx.valid <= wr_beat_valid;
        c1Tx.data <= host_mem_to_afu.wr_writedata;

        c1Tx.hdr <= t_ccip_c1_ReqMemHdr'(0);
        c1Tx.hdr.address <= host_mem_to_afu.wr_address;
        c1Tx.hdr.address[1:0] <= host_mem_to_afu.wr_address[1:0] | wr_cl_num;
        c1Tx.hdr.req_type <= eREQ_WRLINE_I;
        c1Tx.hdr.sop <= wr_sop;
        c1Tx.hdr.cl_len <= wr_sop ? t_ccip_clLen'(host_mem_to_afu.wr_burstcount - 3'b1) : wr_cl_len;

        // Update multi-line state
        if (wr_beat_valid)
        begin
            if (wr_sop)
            begin
                wr_cl_len <= t_ccip_clLen'(host_mem_to_afu.wr_burstcount - 3'b1);
            end

            if (wr_eop)
            begin
                wr_sop <= 1'b1;
                wr_cl_num <= t_ccip_clNum'(0);
            end
            else
            begin
                wr_sop <= 1'b0;
                wr_cl_num <= wr_cl_num + t_ccip_clNum'(1);
            end
        end

        if (reset)
        begin
            c1Tx.valid <= 1'b0;
            wr_sop <= 1'b1;
            wr_cl_len <= eCL_LEN_1;
            wr_cl_num <= t_ccip_clNum'(0);
        end
    end

    // CCI-P write responses are already packed and sorted. Just forward them to
    // Avalon.
    always_ff @(posedge clk)
    begin
        host_mem_to_afu.wr_writeresponsevalid <= ccip_c1Rx_isWriteRsp(sRx.c1);

        if (reset)
        begin
            host_mem_to_afu.wr_writeresponsevalid <= 1'b0;
        end
    end

    assign host_mem_to_afu.wr_response = 2'b0;

endmodule // ofs_plat_map_ccip_as_avalon_host_mem
