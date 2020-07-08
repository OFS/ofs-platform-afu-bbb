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
// Manage a space of unique IDs for tagging transactions.
//

module ofs_plat_prim_uid
  #(
    parameter N_ENTRIES = 32,
    // Number of low entries to reserve that will never be allocated
    parameter N_RESERVED = 0
    )
   (
    input  logic clk,
    input  logic reset_n,

    // Allocate an entry. Ignored when !alloc_ready.
    input  logic alloc,
    // Is an entry available?
    output logic alloc_ready,
    // Assigned UID -- valid as long as notFull is set
    output logic [$clog2(N_ENTRIES)-1 : 0] alloc_uid,

    // Release a UID
    input  logic free,
    input  logic [$clog2(N_ENTRIES)-1 : 0] free_uid
    );

    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_uid;

    logic need_uid;

    //
    // Tracking memory. A bit is 1 when busy and 0 when available. We need
    // only one write port, allowing a UID to either be allocated or freed
    // in a cycle but not both. The case where both happen in the same
    // cycle is handled specially to avoid the conflict: the freed UID
    // is reused for the allocation.
    //

    logic test_ready;
    t_uid test_uid;
    logic test_uid_busy;

    logic wen;
    t_uid waddr;
    logic wdata;

    ofs_plat_prim_lutram_init
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(1)
        )
      tracker
       (
        .clk,
        .reset_n,
        .rdy(test_ready),

        .wen,
        .waddr,
        .wdata,

        .raddr(test_uid),
        .rdata(test_uid_busy)
        );


    //
    // Inbound freed UIDs
    //
    logic free_q;
    t_uid free_uid_q;

    always_ff @(posedge clk)
    begin
        free_q <= free;
        free_uid_q <= free_uid;
    end;


    //
    // Loop through the tracker memory looking for a free UID.
    // When a free UID is found the tracker waits for it to be needed
    // and then resumes the search.
    //
    always_ff @(posedge clk)
    begin
        // Move to the next entry if the current entry is busy or was
        // allocated this cycle.
        if (test_uid_busy || (need_uid && !free_q))
        begin
            test_uid <= test_uid + 1;
            if (test_uid == t_uid'(N_ENTRIES-1))
            begin
                test_uid <= N_RESERVED;
            end
        end

        if (!reset_n || !test_ready)
        begin
            test_uid <= N_RESERVED;
        end
    end


    //
    // Update the tracker
    //
    always_comb
    begin
        if (need_uid && free_q)
        begin
            // Allocate and free on the same cycle. The freed UID will be
            // reused instead of updating the tracker.
            wen = 1'b0;
            waddr = 'x;
            wdata = 'x;
        end
        else if (free_q)
        begin
            // Release free_uid_q. No allocation.
            wen = 1'b1;
            waddr = free_uid_q;
            wdata = 1'b0;
        end
        else
        begin
            // Maybe an allocation.
            wen = need_uid && test_ready;
            waddr = test_uid;
            wdata = 1'b1;
        end
    end


    //
    // Push allocated UIDs to an outbound FIFO. The client will consume
    // UIDs from the FIFO.
    //
    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS($bits(t_uid))
        )
      out_fifo
       (
        .clk,
        .reset_n,

        // When a new UID is needed, pick either the one being freed this
        // cycle (if available) or a new one (if available).
        .enq_data(free_q ? free_uid_q : test_uid),
        .enq_en(need_uid && test_ready && (free_q || !test_uid_busy)),
        .notFull(need_uid),

        .first(alloc_uid),
        .deq_en(alloc && alloc_ready),
        .notEmpty(alloc_ready)
        );

endmodule // ofs_plat_prim_uid
