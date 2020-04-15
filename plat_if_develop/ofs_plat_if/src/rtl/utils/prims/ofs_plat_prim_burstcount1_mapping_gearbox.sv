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
// These modules operate on burst counts with an origin of 1, where "1" means
// one beat and "0" is illegal. This is the Avalon encoding.
//

//
// When a master and slave have different maximum burst counts this gearbox
// turns each master command into one or more slave commands. The gearbox
// can also enforce natural alignment in the slave, ensuring that the low
// address bits reflect the flit count within a bust. This is required
// by some protocols, e.g. CCI-P.
//

module ofs_plat_prim_burstcount1_mapping_gearbox
  #(
    parameter ADDR_WIDTH = 0,
    parameter MASTER_BURST_WIDTH = 0,
    parameter SLAVE_BURST_WIDTH = 0,
    parameter NATURAL_ALIGNMENT = 0
    )
   (
    input  logic clk,
    input  logic reset_n,

    input  logic m_new_req,
    input  logic [ADDR_WIDTH-1 : 0] m_addr,
    input  logic [MASTER_BURST_WIDTH-1 : 0] m_burstcount,

    input  logic s_accept_req,
    output logic s_req_complete,
    output logic [ADDR_WIDTH-1 : 0] s_addr,
    output logic [SLAVE_BURST_WIDTH-1 : 0] s_burstcount
    );

    // Pick an implementation. Natural alignment is more complex, so use
    // it only when necessary.
    generate
        if (NATURAL_ALIGNMENT == 0)
        begin : s
            ofs_plat_prim_burstcount1_simple_mapping_gearbox
              #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .MASTER_BURST_WIDTH(MASTER_BURST_WIDTH),
                .SLAVE_BURST_WIDTH(SLAVE_BURST_WIDTH)
                )
              map
               (
                .clk,
                .reset_n,
                .m_new_req,
                .m_addr,
                .m_burstcount,
                .s_accept_req,
                .s_req_complete,
                .s_addr,
                .s_burstcount
                );
        end
        else
        begin : n
            ofs_plat_prim_burstcount1_natural_mapping_gearbox
              #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .MASTER_BURST_WIDTH(MASTER_BURST_WIDTH),
                .SLAVE_BURST_WIDTH(SLAVE_BURST_WIDTH)
                )
              map
               (
                .clk,
                .reset_n,
                .m_new_req,
                .m_addr,
                .m_burstcount,
                .s_accept_req,
                .s_req_complete,
                .s_addr,
                .s_burstcount
                );
        end
    endgenerate

endmodule // ofs_plat_prim_burstcount1_mapping_gearbox


//
// Simple mapping without alignment enforcement. The only requirement
// is that bursts must fit in the slave's encoding.
//
module ofs_plat_prim_burstcount1_simple_mapping_gearbox
  #(
    parameter ADDR_WIDTH = 0,
    parameter MASTER_BURST_WIDTH = 0,
    parameter SLAVE_BURST_WIDTH = 0
    )
   (
    input  logic clk,
    input  logic reset_n,

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
    // Can the master burst request be encoded as a slave burst?
    //
    function automatic logic next_burst_is_last(t_master_burst_cnt burst_req);
        logic not_last =
              ((SLAVE_BURST_WIDTH < MASTER_BURST_WIDTH) &&
               (burst_req > t_master_burst_cnt'(SLAVE_MAX_BURST)));

        return !not_last;
    endfunction // next_burst_is_last

    t_master_burst_cnt burstcount;

    always_ff @(posedge clk)
    begin
        if (m_new_req)
        begin
            // New request -- the last one is complete
            burstcount <= m_burstcount;
            s_req_complete <= next_burst_is_last(m_burstcount);
            s_addr <= m_addr;
        end
        else if (s_accept_req)
        begin
            // The existing request is only partially transmitted. Underflow
            // in the next cycle's remaining burst is irrelevant since
            // s_req_complete will stop the burst. Just subtract the max slave
            // burst instead of the correct s_burstcount.
            burstcount <= burstcount - t_master_burst_cnt'(SLAVE_MAX_BURST);
            s_req_complete <= (burstcount <= t_master_burst_cnt'(2 * SLAVE_MAX_BURST));
            s_addr <= s_addr + t_addr'(SLAVE_MAX_BURST);
        end

        if (!reset_n)
        begin
            burstcount <= t_master_burst_cnt'(0);
            s_req_complete <= 1'b1;
        end
    end

    // Pick a legal burst count in the slave (at most SLAVE_MAX_BURST).
    assign s_burstcount = s_req_complete ?
                              t_slave_burst_cnt'(burstcount) :
                              t_slave_burst_cnt'(SLAVE_MAX_BURST);

endmodule // ofs_plat_prim_burstcount1_simple_mapping_gearbox


module ofs_plat_prim_burstcount1_natural_mapping_gearbox
  #(
    parameter ADDR_WIDTH = 0,
    parameter MASTER_BURST_WIDTH = 0,
    parameter SLAVE_BURST_WIDTH = 0,
    parameter NATURAL_ALIGNMENT = 1
    )
   (
    input  logic clk,
    input  logic reset_n,

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
    // Calculate whether the combination of the master burst_req and the
    // current address can be encoded in a single slave burst.
    //
    function automatic logic next_burst_is_last(t_master_burst_cnt burst_req,
                                                t_addr addr);
        logic not_last =
              // Burst is larger than slave's maximum
              (burst_req > t_master_burst_cnt'(SLAVE_MAX_BURST)) ||
              // More than one bit is set in burst_req -- can only send one at a time
              |(burst_req & (burst_req - 1)) ||
              // Address isn't aligned to burst size
              |(t_slave_burst_cnt'((burst_req - 1) & addr));

        return !not_last;
    endfunction // next_burst_is_last

    //
    // Compute the maximum naturally aligned burst count for the burst request
    // and address.
    //
    function automatic t_slave_burst_cnt aligned_burst_max(t_master_burst_cnt burst_req,
                                                           t_addr addr);
        // The limit to the burst width is the minimum of the slave and master
        // burst sizes.
        int burst_width_limit = (SLAVE_BURST_WIDTH < MASTER_BURST_WIDTH) ? SLAVE_BURST_WIDTH : MASTER_BURST_WIDTH;

        // Find the first one in the low bits of either address or request size
        for (int i = 0; i < burst_width_limit; i = i + 1)
        begin
            if (burst_req[i] || addr[i])
            begin
                return t_slave_burst_cnt'(1 << i);
            end
        end

        // This point is reached only when the requested burst size exceeds
        // SLAVE_MAX_BURST and SLAVE_MAX_BURST is a legal aligned request.
        return t_master_burst_cnt'(SLAVE_MAX_BURST);
    endfunction // aligned_burst_max

    t_master_burst_cnt burstcount, burstcount_masked;

    t_master_burst_cnt next_burstcount;
    assign next_burstcount = burstcount - t_master_burst_cnt'(s_burstcount);

    always_ff @(posedge clk)
    begin
        if (m_new_req)
        begin
            // New request -- the last one is complete
            burstcount <= m_burstcount;
            burstcount_masked <= only_highest_one(m_burstcount);
            s_addr <= m_addr;
            s_req_complete <= next_burst_is_last(m_burstcount, m_addr);
        end
        else if (s_accept_req)
        begin
            // The existing request is only partially transmitted
            burstcount <= next_burstcount;
            burstcount_masked <= only_highest_one(next_burstcount);
            s_addr <= s_addr + t_addr'(s_burstcount);
            s_req_complete <= next_burst_is_last(next_burstcount,
                                                 s_addr + t_addr'(s_burstcount));
        end

        if (!reset_n)
        begin
            burstcount <= t_master_burst_cnt'(0);
            burstcount_masked <= t_master_burst_cnt'(0);
        end
    end

    // Pick a legal burst count in the slave.
    assign s_burstcount = aligned_burst_max(burstcount_masked, s_addr);

endmodule // ofs_plat_prim_burstcount1_natural_mapping_gearbox
