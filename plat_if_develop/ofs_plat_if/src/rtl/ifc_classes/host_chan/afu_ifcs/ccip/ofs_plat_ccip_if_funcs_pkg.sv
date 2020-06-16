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
// Utility functions that evaluate or update CCI-P data types.
//

`ifdef PLATFORM_IF_AVAIL
`include "platform_if.vh"
`endif

package ofs_plat_ccip_if_funcs_pkg;

    import ccip_if_pkg::*;

    function automatic t_if_ccip_c0_Tx ccip_c0Tx_clearValids();
        t_if_ccip_c0_Tx r = 'x;
        r.valid = 1'b0;
        return r;
    endfunction

    function automatic t_if_ccip_c1_Tx ccip_c1Tx_clearValids();
        t_if_ccip_c1_Tx r = 'x;
        r.valid = 1'b0;
        return r;
    endfunction

    function automatic t_if_ccip_c2_Tx ccip_c2Tx_clearValids();
        t_if_ccip_c2_Tx r = 'x;
        r.mmioRdValid = 0;
        return r;
    endfunction

    function automatic t_if_ccip_c0_Rx ccip_c0Rx_clearValids();
        t_if_ccip_c0_Rx r = 'x;
        r.rspValid = 0;
        r.mmioRdValid = 0;
        r.mmioWrValid = 0;
        return r;
    endfunction

    function automatic t_if_ccip_c1_Rx ccip_c1Rx_clearValids();
        t_if_ccip_c1_Rx r = 'x;
        r.rspValid = 0;
        return r;
    endfunction

    function automatic logic ccip_c0Rx_isValid(
        input t_if_ccip_c0_Rx r
        );

        return r.rspValid ||
               r.mmioRdValid ||
               r.mmioWrValid;
    endfunction

    function automatic logic ccip_c0Tx_isReadReq_noCheckValid(
        input t_if_ccip_c0_Tx r
        );

        return ((r.hdr.req_type == eREQ_RDLINE_I) ||
                (r.hdr.req_type == eREQ_RDLINE_S) ||
                (r.hdr.req_type == eREQ_RDLSPEC_I) ||
                (r.hdr.req_type == eREQ_RDLSPEC_S)
                );
    endfunction

    function automatic logic ccip_c0Tx_isReadReq(
        input t_if_ccip_c0_Tx r
        );

        return r.valid && ccip_c0Tx_isReadReq_noCheckValid(r);
    endfunction

    function automatic logic ccip_c0Tx_isSpecReadReq_noCheckValid(
        input t_if_ccip_c0_Tx r
        );

        return ((r.hdr.req_type == eREQ_RDLSPEC_I) ||
                (r.hdr.req_type == eREQ_RDLSPEC_S));
    endfunction

    function automatic logic ccip_c0Tx_isSpecReadReq(
        input t_if_ccip_c0_Tx r
        );

        return r.valid && ccip_c0Tx_isSpecReadReq_noCheckValid(r);
    endfunction

    function automatic logic ccip_c0Rx_isReadRsp(
        input t_if_ccip_c0_Rx r
        );

        return r.rspValid && (r.hdr.resp_type == eRSP_RDLINE);
    endfunction

    function automatic logic ccip_c0Rx_isError(
        input t_if_ccip_c0_Rx r
        );
        // Speculative translation error? This field was added
        // later, so we must test whether it is supported.
`ifdef CCIP_ENCODING_HAS_RDLSPEC
        return r.hdr.error;
`else
        return 1'b0;
`endif
    endfunction

    function automatic logic ccip_c1Tx_isValid(
        input t_if_ccip_c1_Tx r
        );

        return r.valid;
    endfunction

    function automatic logic ccip_c1Tx_isWriteReq_noCheckValid(
        input t_if_ccip_c1_Tx r
        );

        return ((r.hdr.req_type == eREQ_WRLINE_I) ||
                (r.hdr.req_type == eREQ_WRLINE_M) ||
                (r.hdr.req_type == eREQ_WRPUSH_I));
    endfunction

    function automatic logic ccip_c1Tx_isWriteReq(
        input t_if_ccip_c1_Tx r
        );

        return r.valid && ccip_c1Tx_isWriteReq_noCheckValid(r);
    endfunction

    function automatic logic ccip_c1Tx_isWriteFenceReq_noCheckValid(
        input t_if_ccip_c1_Tx r
        );

        return (r.hdr.req_type == eREQ_WRFENCE);
    endfunction

    function automatic logic ccip_c1Tx_isWriteFenceReq(
        input t_if_ccip_c1_Tx r
        );

        return r.valid && ccip_c1Tx_isWriteFenceReq_noCheckValid(r);
    endfunction

    function automatic logic ccip_c1Tx_isInterruptReq_noCheckValid(
        input t_if_ccip_c1_Tx r
        );

        return (r.hdr.req_type == eREQ_INTR);
    endfunction

    function automatic logic ccip_c1Tx_isInterruptReq(
        input t_if_ccip_c1_Tx r
        );

        return r.valid && ccip_c1Tx_isInterruptReq_noCheckValid(r);
    endfunction

    function automatic logic ccip_c1Tx_isByteRange(
        input t_if_ccip_c1_Tx r
        );

        return (r.hdr.mode == eMOD_BYTE);
    endfunction

    function automatic logic ccip_c1Rx_isValid(
        input t_if_ccip_c1_Rx r
        );

        return r.rspValid;
    endfunction

    function automatic logic ccip_c1Rx_isWriteRsp(
        input t_if_ccip_c1_Rx r
        );

        return r.rspValid && (r.hdr.resp_type == eRSP_WRLINE);
    endfunction

    function automatic logic ccip_c1Rx_isWriteFenceRsp(
        input t_if_ccip_c1_Rx r
        );

        return r.rspValid && (r.hdr.resp_type == eRSP_WRFENCE);
    endfunction

    function automatic logic ccip_c1Rx_isInterruptRsp(
        input t_if_ccip_c1_Rx r
        );

        return r.rspValid && (r.hdr.resp_type == eRSP_INTR);
    endfunction

endpackage // ofs_plat_ccip_if_funcs_pkg
