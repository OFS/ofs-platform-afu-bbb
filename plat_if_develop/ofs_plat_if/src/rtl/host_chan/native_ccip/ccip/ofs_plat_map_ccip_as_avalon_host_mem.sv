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
    // CCI-P interface to FIU
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    // Generated Avalon host memory interface
    ofs_plat_avalon_mem_rdwr_if.to_master_clk host_mem_to_afu
    );

    import ofs_plat_ccip_if_funcs_pkg::*;

    logic clk;
    assign clk = to_fiu.clk;

    logic reset;
    assign reset = to_fiu.reset;

    t_if_ccip_Rx sRx;
    assign sRx = to_fiu.sRx;

    // Tie off sTx.c2. MMIO should have been split off before passing to_fiu
    // to this module.
    assign to_fiu.sTx.c2 = t_if_ccip_c2_Tx'(0);


    //
    // The AFU has set the burst count width of host_mem_to_afu to whatever
    // is expected by the AFU. CCI-P requires bursts no larger than 4 lines.
    // The bursts must also be naturally aligned. Transform host_mem_to_afu
    // bursts to legal CCI-P bursts.
    //

    ofs_plat_avalon_mem_rdwr_if
      #(
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN),
        `ofs_plat_avalon_mem_rdwr_if_replicate_params(host_mem_to_afu)
        )
      avmm_afu_burst_if();

    ofs_plat_avalon_mem_rdwr_if_connect_slave_clk
      conn_clk
       (
        .mem_master(host_mem_to_afu),
        .mem_slave(avmm_afu_burst_if)
        );

    // Limit burst count to 4 on the FIU side
    ofs_plat_avalon_mem_rdwr_if
      #(
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN),
        `ofs_plat_avalon_mem_rdwr_if_replicate_mem_params(host_mem_to_afu),
        .BURST_CNT_WIDTH(3)
        )
      avmm_fiu_burst_if();

    logic fiu_burst_expects_response;
    ofs_plat_avalon_mem_rdwr_if_map_bursts
      #(
        .NATURAL_ALIGNMENT(1)
        )
      map_bursts
       (
        .mem_master(avmm_afu_burst_if),
        .mem_slave(avmm_fiu_burst_if),
        .wr_slave_burst_expects_response(fiu_burst_expects_response)
        );

    assign avmm_afu_burst_if.clk = clk;
    assign avmm_afu_burst_if.reset = reset;
    assign avmm_afu_burst_if.instance_number = to_fiu.instance_number;
    assign avmm_fiu_burst_if.clk = clk;
    assign avmm_fiu_burst_if.reset = reset;
    assign avmm_fiu_burst_if.instance_number = to_fiu.instance_number;

    // Map almost full to Avalon waitrequest
    always_ff @(posedge clk)
    begin
        avmm_fiu_burst_if.rd_waitrequest <= sRx.c0TxAlmFull;
        avmm_fiu_burst_if.wr_waitrequest <= sRx.c1TxAlmFull;
    end

    //
    // Host memory reads
    //
    always_ff @(posedge clk)
    begin
        to_fiu.sTx.c0.valid <= avmm_fiu_burst_if.rd_read && ! avmm_fiu_burst_if.rd_waitrequest;

        to_fiu.sTx.c0.hdr <= t_ccip_c0_ReqMemHdr'(0);
        to_fiu.sTx.c0.hdr.address <= avmm_fiu_burst_if.rd_address;
        to_fiu.sTx.c0.hdr.req_type <= eREQ_RDLINE_I;
        to_fiu.sTx.c0.hdr.cl_len <= t_ccip_clLen'(avmm_fiu_burst_if.rd_burstcount - 3'b1);

        if (reset)
        begin
            to_fiu.sTx.c0.valid <= 1'b0;
        end
    end

    // CCI-P responses are already sorted. Just forward them to Avalon.
    always_ff @(posedge clk)
    begin
        avmm_fiu_burst_if.rd_readdatavalid <= ccip_c0Rx_isReadRsp(sRx.c0);
        avmm_fiu_burst_if.rd_readdata <= sRx.c0.data;

        if (reset)
        begin
            avmm_fiu_burst_if.rd_readdatavalid <= 1'b0;
        end
    end

    assign avmm_fiu_burst_if.rd_response = 2'b0;

    //
    // Host memory writes
    //
    logic wr_beat_valid;
    assign wr_beat_valid = avmm_fiu_burst_if.wr_write && ! avmm_fiu_burst_if.wr_waitrequest;

    logic wr_sop;
    t_ccip_clLen wr_cl_len;
    t_ccip_clNum wr_cl_num;
    t_ccip_clNum wr_cl_addr;

    // Is the current incoming write line the end of a packet? It is if either
    // starting a new single-line packet or all lines of a multi-line
    // package have now arrived.
    logic wr_eop;
    assign wr_eop = (wr_sop && (avmm_fiu_burst_if.wr_burstcount == 3'b1)) ||
                    (!wr_sop && (wr_cl_num == t_ccip_clNum'(wr_cl_len)));

    always_ff @(posedge clk)
    begin
        to_fiu.sTx.c1.valid <= wr_beat_valid;
        to_fiu.sTx.c1.data <= avmm_fiu_burst_if.wr_writedata;

        if (wr_sop)
        begin
            to_fiu.sTx.c1.hdr <= t_ccip_c1_ReqMemHdr'(0);
            to_fiu.sTx.c1.hdr.mdata[0] <= fiu_burst_expects_response;

            if (! avmm_fiu_burst_if.wr_request)
            begin
                // Normal write
                to_fiu.sTx.c1.hdr.address <= avmm_fiu_burst_if.wr_address;
                to_fiu.sTx.c1.hdr.req_type <= eREQ_WRLINE_I;
                to_fiu.sTx.c1.hdr.cl_len <= t_ccip_clLen'(avmm_fiu_burst_if.wr_burstcount - 3'b1);
                to_fiu.sTx.c1.hdr.sop <= 1'b1;
            end
            else
            begin
                // Write fence. req_type and mdata are in the same places in the
                // header as a normal write.
                to_fiu.sTx.c1.hdr.req_type <= eREQ_WRFENCE;
            end
        end
        else
        begin
            to_fiu.sTx.c1.hdr.address[1:0] <= wr_cl_addr | wr_cl_num;
            to_fiu.sTx.c1.hdr.sop <= 1'b0;
        end

        // Update multi-line state
        if (wr_beat_valid)
        begin
            if (wr_sop)
            begin
                wr_cl_len <= t_ccip_clLen'(avmm_fiu_burst_if.wr_burstcount - 3'b1);
                wr_cl_addr <= t_ccip_clNum'(avmm_fiu_burst_if.wr_address);
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
            to_fiu.sTx.c1.valid <= 1'b0;
            wr_sop <= 1'b1;
            wr_cl_len <= eCL_LEN_1;
            wr_cl_num <= t_ccip_clNum'(0);
        end
    end

    // CCI-P write responses are already packed and sorted. Just forward them to
    // Avalon. Bit 0 of mdata records whether the write expects a response.
    always_ff @(posedge clk)
    begin
        avmm_fiu_burst_if.wr_writeresponsevalid <=
            (ccip_c1Rx_isWriteRsp(sRx.c1) || ccip_c1Rx_isWriteFenceRsp(sRx.c1)) &&
            sRx.c1.hdr.mdata[0];

        if (reset)
        begin
            avmm_fiu_burst_if.wr_writeresponsevalid <= 1'b0;
        end
    end

    assign avmm_fiu_burst_if.wr_response = 2'b0;

endmodule // ofs_plat_map_ccip_as_avalon_host_mem
