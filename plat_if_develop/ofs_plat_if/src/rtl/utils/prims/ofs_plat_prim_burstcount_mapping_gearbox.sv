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
    // Leave only the highest one found in burst_req. Everything below it
    // will be cleared, leaving a single bit set for the burst size.
    //
    function automatic t_master_burst_cnt only_highest_one(t_master_burst_cnt burst_req);
        t_master_burst_cnt aligned_burst_req;
        logic found_one = 1'b0;

        for (int i = MASTER_BURST_WIDTH - 1; i >= 0; i = i - 1)
        begin
            aligned_burst_req[i] = burst_req[i] & ! found_one;
            found_one = burst_req[i] | found_one;
        end

        return aligned_burst_req;
    endfunction // only_highest_one

    //
    // Compute the maximum naturally aligned burst count for the burst request
    // and address.
    //
    function automatic t_master_burst_cnt aligned_burst_max(t_master_burst_cnt burst_req,
                                                            t_addr addr);
        // The limit to the burst width is the minimum of the slave and master
        // burst sizes.
        int burst_width_limit = (SLAVE_BURST_WIDTH < MASTER_BURST_WIDTH) ? SLAVE_BURST_WIDTH : MASTER_BURST_WIDTH;

        // Find the first one in the low bits of either address or request size
        for (int i = 0; i < burst_width_limit; i = i + 1)
        begin
            if (burst_req[i] || addr[i])
            begin
                return t_master_burst_cnt'(1 << i);
            end
        end

        // This point is reached only when the requested burst size exceeds
        // SLAVE_MAX_BURST and SLAVE_MAX_BURST is a legal aligned request.
        return t_master_burst_cnt'(SLAVE_MAX_BURST);
    endfunction // aligned_burst_max

    //
    // Compute a legal burst count given a requested count and the current address.
    //
    function automatic t_slave_burst_cnt compute_burstcount(t_master_burst_cnt burst_req,
                                                            t_master_burst_cnt burst_req_masked,
                                                            t_addr addr);
        // Does the slave require naturally aligned addresses and sizes?
        if (NATURAL_ALIGNMENT)
        begin
            return t_slave_burst_cnt'(aligned_burst_max(burst_req_masked, addr));
        end
        else
        begin
            t_master_burst_cnt bmax = burst_req;

            // If the requested count exceeds the maximum count that is valid in the
            // slave then reduce the request to the slave's maximum.
            if ((SLAVE_BURST_WIDTH < MASTER_BURST_WIDTH) &&
                (burst_req > t_master_burst_cnt'(SLAVE_MAX_BURST)))
            begin
                bmax = t_master_burst_cnt'(SLAVE_MAX_BURST);
            end

            return t_slave_burst_cnt'(bmax);
        end

    endfunction // compute_burstcount

    t_master_burst_cnt burstcount, burstcount_masked;

    always_ff @(posedge clk)
    begin
        if (m_new_req)
        begin
            // New request -- the last one is complete
            burstcount <= m_burstcount;
            burstcount_masked <= only_highest_one(m_burstcount);
            s_addr <= m_addr;
        end
        else if (s_accept_req)
        begin
            // The existing request is only partially transmitted
            burstcount <= burstcount - t_master_burst_cnt'(s_burstcount);
            burstcount_masked <= only_highest_one(burstcount - t_master_burst_cnt'(s_burstcount));
            s_addr <= s_addr + t_addr'(s_burstcount);
        end

        if (reset)
        begin
            burstcount <= t_master_burst_cnt'(0);
            burstcount_masked <= t_master_burst_cnt'(0);
        end
    end

    // Pick a legal burst count in the slave.
    assign s_burstcount = compute_burstcount(burstcount, burstcount_masked, s_addr);
    assign s_req_complete = (t_master_burst_cnt'(s_burstcount) == burstcount);

endmodule // ofs_plat_prim_burstcount_mapping_gearbox
