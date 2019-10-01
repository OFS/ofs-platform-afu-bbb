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

//
// CCI-P host interface.
//

`include "ofs_plat_if.vh"

interface ofs_plat_host_ccip_if
  #(
    // Log events for this instance?
    parameter ofs_plat_log_pkg::t_log_class LOG_CLASS = ofs_plat_log_pkg::NONE
    );

    wire clk;
    logic reset;    // ACTIVE HIGH

    // CCI-P Protocol Error Detected
    logic error;

    // The CCI-P interface predates stable support for SystemVerilog interfaces,
    // so uses structs to wrap all signals.

    // CCI-P Rx Port
    t_if_ccip_Rx sRx;
    // CCI-P Tx Port
    t_if_ccip_Tx sTx;

    //
    // Connection to the platform (FPGA Interface Manager)
    //
    modport to_fiu
       (
        input  clk,
        input  reset,
        input  error,
        input  sRx,
        output sTx
        );

    //
    // Connection to the AFU (user logic)
    //
    modport to_afu
       (
        output clk,
        output reset,
        output error,
        output sRx,
        input  sTx
        );


    //
    // Debugging
    //

    // synthesis translate_off

    // Print Channel function
    function string print_channel (logic [1:0] vc_sel);
        case (vc_sel)
            2'b00: return "VA ";
            2'b01: return "VL0";
            2'b10: return "VH0";
            2'b11: return "VH1";
        endcase
    endfunction

    // Print Req Type
    function string print_c0_reqtype (t_ccip_c0_req req);
        case (req)
            eREQ_RDLINE_S: return "RdLine_S  ";
            eREQ_RDLINE_I: return "RdLine_I  ";
            eREQ_RDLSPEC_S: return "RdLSpec_S ";
            eREQ_RDLSPEC_I: return "RdLSpec_I ";
            default:       return "* c0 REQ ERROR * ";
        endcase
    endfunction

    function string print_c1_reqtype (t_ccip_c1_req req);
        case (req)
            eREQ_WRLINE_I: return "WrLine_I  ";
            eREQ_WRLINE_M: return "WrLine_M  ";
            eREQ_WRPUSH_I: return "WrPush_I  ";
            eREQ_WRFENCE:  return "WrFence   ";
         // eREQ_ATOMIC:   return "Atomic    ";
            eREQ_INTR:     return "IntrReq   ";
            default:       return "* c1 REQ ERROR * ";
        endcase
    endfunction

    // Print resp type
    function string print_c0_resptype (t_ccip_c0_rsp rsp);
        case (rsp)
            eRSP_RDLINE:  return "RdRsp      ";
            eRSP_UMSG:    return "UmsgRsp    ";
         // eRSP_ATOMIC:  return "AtomicRsp  ";
            default:      return "* c0 RSP ERROR *  ";
        endcase
    endfunction

    function string print_c1_resptype (t_ccip_c1_rsp rsp);
        case (rsp)
            eRSP_WRLINE:  return "WrRsp      ";
            eRSP_WRFENCE: return "WrFenceRsp ";
            eRSP_INTR:    return "IntrResp   ";
            default:      return "* c1 RSP ERROR *  ";
        endcase
    endfunction

    // Print CSR data
    function int csr_len(logic [1:0] length);
        case (length)
            2'b0: return 4;
            2'b1: return 8;
            2'b10: return 64;
            default: return 0;
        endcase
    endfunction

    initial
    begin : logger_proc
        // Watch traffic
        if (LOG_CLASS != ofs_plat_log_pkg::NONE)
        begin
            static int log_fd = ofs_plat_log_pkg::get_fd(LOG_CLASS);

            forever @(posedge clk)
            begin
                // //////////////////////// C0 TX CHANNEL TRANSACTIONS //////////////////////////
                /******************* AFU -> MEM Read Request ******************/
                if (! reset && sTx.c0.valid)
                begin
                    $fwrite(log_fd, "%m:\t%t\t%s\t%0d\t%s\t%x\t%x\n",
                            $time,
                            print_channel(sTx.c0.hdr.vc_sel),
                            sTx.c0.hdr.cl_len,
                            print_c0_reqtype(sTx.c0.hdr.req_type),
                            sTx.c0.hdr.mdata,
                            sTx.c0.hdr.address);

                end

                //////////////////////// C1 TX CHANNEL TRANSACTIONS //////////////////////////
                /******************* AFU -> MEM Write Request *****************/
                if (! reset && sTx.c1.valid)
                begin
                    $fwrite(log_fd, "%m:\t%t\t%s\t%0d\t%s\t%s\t%x\t%x\t%x",
                            $time,
                            print_channel(sTx.c1.hdr.vc_sel),
                            sTx.c1.hdr.cl_len,
                            (sTx.c1.hdr.sop ? "S" : "x"),
                            print_c1_reqtype(sTx.c1.hdr.req_type),
                            sTx.c1.hdr.mdata,
                            sTx.c1.hdr.address,
                            sTx.c1.data);

                    if (sTx.c1.hdr.mode == eMOD_BYTE)
                    begin
                        $fwrite(log_fd, " PW [start %0d, len %0d]",
                                sTx.c1.hdr.byte_start, sTx.c1.hdr.byte_len);
                    end

                    $fwrite(log_fd, "\n");
                end

                //////////////////////// C2 TX CHANNEL TRANSACTIONS //////////////////////////
                /******************* AFU -> MMIO Read Response *****************/
                if (! reset && sTx.c2.mmioRdValid)
                begin
                    $fwrite(log_fd, "%m:\t%t\tMMIORdRsp\t%x\t%x\n",
                            $time,
                            sTx.c2.hdr.tid,
                            sTx.c2.data);
                end

                //////////////////////// C0 RX CHANNEL TRANSACTIONS //////////////////////////
                /******************* MEM -> AFU Read Response *****************/
                if (! reset && sRx.c0.rspValid)
                begin
                    $fwrite(log_fd, "%m:\t%t\t%s\t%0d\t%s%s\t%x\t%x\n",
                            $time,
                            print_channel(sRx.c0.hdr.vc_used),
                            sRx.c0.hdr.cl_num,
                            print_c0_resptype(sRx.c0.hdr.resp_type),
                            (sRx.c0.hdr.error ? "ERROR " : ""),
                            sRx.c0.hdr.mdata,
                            sRx.c0.data);
                end

                /****************** MEM -> AFU Write Response *****************/
                if (! reset && sRx.c1.rspValid)
                begin
                    $fwrite(log_fd, "%m:\t%t\t%s\t%0d\t%s\t%s\t%x\n",
                            $time,
                            print_channel(sRx.c1.hdr.vc_used),
                            sRx.c1.hdr.cl_num,
                            (sRx.c1.hdr.format ? "F" : "x"),
                            print_c1_resptype(sRx.c1.hdr.resp_type),
                            sRx.c1.hdr.mdata);
                end

                /******************* SW -> AFU Config Write *******************/
                if (! reset && sRx.c0.mmioWrValid)
                begin
                    t_ccip_c0_ReqMmioHdr mmio_hdr;
                    mmio_hdr = t_ccip_c0_ReqMmioHdr'(sRx.c0.hdr);

                    $fwrite(log_fd, "%m:\t%t\tMMIOWrReq\t%x\t%d bytes\t%x\t%x\n",
                            $time,
                            mmio_hdr.tid,
                            csr_len(mmio_hdr.length),
                            mmio_hdr.address,
                            sRx.c0.data[63:0]);
                end

                /******************* SW -> AFU Config Read *******************/
                if (! reset && sRx.c0.mmioRdValid)
                begin
                    t_ccip_c0_ReqMmioHdr mmio_hdr;
                    mmio_hdr = t_ccip_c0_ReqMmioHdr'(sRx.c0.hdr);

                    $fwrite(log_fd, "%m:\t%t\tMMIORdReq\t%x\t%d bytes\t%x\n",
                            $time,
                            mmio_hdr.tid,
                            csr_len(mmio_hdr.length),
                            mmio_hdr.address);
                end
            end
        end
    end

    // synthesis translate_on

endinterface // ofs_plat_host_ccip_if
