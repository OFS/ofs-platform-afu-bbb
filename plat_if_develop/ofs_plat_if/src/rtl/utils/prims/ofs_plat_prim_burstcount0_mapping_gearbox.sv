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
// This module operate on burst counts with an origin of 0, where "0" means
// one beat. This is the AXI encoding.
//

//
// When a source and sink have different maximum burst counts this gearbox
// turns each source command into one or more sink commands. The gearbox
// can also enforce natural alignment in the sink, ensuring that the low
// address bits reflect the flit count within a bust. This is required
// by some protocols, e.g. CCI-P.
//

module ofs_plat_prim_burstcount0_mapping_gearbox
  #(
    parameter ADDR_WIDTH = 0,
    parameter SOURCE_BURST_WIDTH = 0,
    parameter SINK_BURST_WIDTH = 0,
    // When non-zero emit only naturally aligned requests.
    parameter NATURAL_ALIGNMENT = 0,
    // When non-zero ensure that no bursts cross page boundaries. Used
    // only when NATURAL_ALIGNMENT is 0.
    // Like ADDR_WIDTH, the PAGE_SIZE is measured in bursts. If the bus
    // is 64 bytes then PAGE_SIZE of 64 is a 4KB page.
    parameter PAGE_SIZE = 0
    )
   (
    input  logic clk,
    input  logic reset_n,

    input  logic m_new_req,
    input  logic [ADDR_WIDTH-1 : 0] m_addr,
    input  logic [SOURCE_BURST_WIDTH-1 : 0] m_burstcount,

    input  logic s_accept_req,
    output logic s_req_complete,
    output logic [ADDR_WIDTH-1 : 0] s_addr,
    output logic [SINK_BURST_WIDTH-1 : 0] s_burstcount
    );

    typedef logic [SOURCE_BURST_WIDTH:0] t_m_burstcount1;

    typedef logic [SINK_BURST_WIDTH:0] t_s_burstcount1;
    t_s_burstcount1 s_b1;
    assign s_burstcount = (s_b1 - 1);

    // Pick an implementation. Natural alignment is more complex, so use
    // it only when necessary.
    generate
        if (NATURAL_ALIGNMENT != 0)
        begin : n
            ofs_plat_prim_burstcount1_natural_mapping_gearbox
              #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .SOURCE_BURST_WIDTH(SOURCE_BURST_WIDTH+1),
                .SINK_BURST_WIDTH(SINK_BURST_WIDTH+1)
                )
              map
               (
                .clk,
                .reset_n,
                .m_new_req,
                .m_addr,
                .m_burstcount(t_m_burstcount1'(m_burstcount) + t_m_burstcount1'(1)),
                .s_accept_req,
                .s_req_complete,
                .s_addr,
                .s_burstcount(s_b1)
                );
        end
        else if (PAGE_SIZE != 0)
        begin : p
            ofs_plat_prim_burstcount1_page_mapping_gearbox
              #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .SOURCE_BURST_WIDTH(SOURCE_BURST_WIDTH+1),
                .SINK_BURST_WIDTH(SINK_BURST_WIDTH+1),
                .PAGE_SIZE(PAGE_SIZE)
                )
              map
               (
                .clk,
                .reset_n,
                .m_new_req,
                .m_addr,
                .m_burstcount(t_m_burstcount1'(m_burstcount) + t_m_burstcount1'(1)),
                .s_accept_req,
                .s_req_complete,
                .s_addr,
                .s_burstcount(s_b1)
                );
        end
        else
        begin : s
            ofs_plat_prim_burstcount1_simple_mapping_gearbox
              #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .SOURCE_BURST_WIDTH(SOURCE_BURST_WIDTH+1),
                .SINK_BURST_WIDTH(SINK_BURST_WIDTH+1)
                )
              map
               (
                .clk,
                .reset_n,
                .m_new_req,
                .m_addr,
                .m_burstcount(t_m_burstcount1'(m_burstcount) + t_m_burstcount1'(1)),
                .s_accept_req,
                .s_req_complete,
                .s_addr,
                .s_burstcount(s_b1)
                );
        end
    endgenerate

endmodule // ofs_plat_prim_burstcount0_mapping_gearbox
