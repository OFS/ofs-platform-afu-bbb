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
// When a master and slave have different maximum burst counts this gearbox
// turns each master command into one or more slave commands. The gearbox
// can also enforce natural alignment in the slave, ensuring that the low
// address bits reflect the flit count within a bust. This is required
// by some protocols, e.g. CCI-P.
//

module ofs_plat_prim_burstcount_mapping_gearbox
  #(
    parameter ADDR_WIDTH = 0,
    parameter MASTER_BURST_WIDTH = 0,
    parameter SLAVE_BURST_WIDTH = 0,
    parameter NATURAL_ALIGNMENT = 0
    )
   (
    input  logic clk,
    input  logic reset,

    input  logic m_new_req,
    input  logic [ADDR_WIDTH-1 : 0] m_addr,
    input  logic [MASTER_BURST_WIDTH-1 : 0] m_burstcount,

    input  logic s_accept_req,
    output logic s_req_complete,
    output logic [ADDR_WIDTH-1 : 0] s_addr,
    output logic [SLAVE_BURST_WIDTH-1 : 0] s_burstcount
    );

    typedef logic [ADDR_WIDTH-1 : 0] t_addr;

    localparam MASTER_MAX_BURST = (1 << (MASTER_BURST_WIDTH-1));
    typedef logic [MASTER_BURST_WIDTH-1 : 0] t_master_burst_cnt;

    localparam SLAVE_MAX_BURST = (1 << (SLAVE_BURST_WIDTH-1));
    typedef logic [SLAVE_BURST_WIDTH-1 : 0] t_slave_burst_cnt;


    //
    // Compute the maximum naturally aligned burst count for the address. This
    // is basically find first non-zero in the low bits of the address.
    //
    function automatic t_master_burst_cnt aligned_burst_max(t_addr addr);
        // The limit to the burst width is the minimum of the slave and master
        // burst sizes.
        int burst_width_limit = (SLAVE_BURST_WIDTH < MASTER_BURST_WIDTH) ? SLAVE_BURST_WIDTH : MASTER_BURST_WIDTH;
        t_master_burst_cnt bmax = (SLAVE_MAX_BURST < MASTER_MAX_BURST) ? SLAVE_MAX_BURST : MASTER_MAX_BURST;

        for (int i = 0; i < burst_width_limit; i = i + 1)
        begin
            if (addr[i])
            begin
                bmax = t_master_burst_cnt'(1 << i);
                break;
            end
        end

        return bmax;
    endfunction // aligned_burst_max


    //
    // Compute a legal burst count given a requested count and the current address.
    //
    function automatic t_slave_burst_cnt compute_burstcount(t_master_burst_cnt burst_req,
                                                            t_addr addr);
        t_master_burst_cnt bmax = burst_req;

        // If the requested count exceeds the maximum count that is valid in the
        // slave then reduce the request to the slave's maximum.
        if ((SLAVE_BURST_WIDTH < MASTER_BURST_WIDTH) &&
            (burst_req > t_master_burst_cnt'(SLAVE_MAX_BURST)))
        begin
            bmax = t_master_burst_cnt'(SLAVE_MAX_BURST);
        end

        // Does the slave require naturally aligned addresses?
        if (NATURAL_ALIGNMENT)
        begin
            t_master_burst_cnt bmax_aligned = aligned_burst_max(addr);
            if (bmax_aligned < bmax)
            begin
                bmax = bmax_aligned;
            end
        end

        return t_slave_burst_cnt'(bmax);
    endfunction // compute_burstcount

    t_master_burst_cnt burstcount;

    always_ff @(posedge clk)
    begin
        if (m_new_req)
        begin
            // New request -- the last one is complete
            burstcount <= m_burstcount;
            s_addr <= m_addr;
        end
        else if (s_accept_req)
        begin
            // The existing request is only partially transmitted
            burstcount <= burstcount - t_master_burst_cnt'(s_burstcount);
            s_addr <= s_addr + t_addr'(s_burstcount);
        end
    end

    // Pick a legal burst count in the slave.
    assign s_burstcount = compute_burstcount(burstcount, s_addr);
    assign s_req_complete = (t_master_burst_cnt'(s_burstcount) == burstcount);

endmodule // ofs_plat_prim_burstcount_mapping_gearbox
