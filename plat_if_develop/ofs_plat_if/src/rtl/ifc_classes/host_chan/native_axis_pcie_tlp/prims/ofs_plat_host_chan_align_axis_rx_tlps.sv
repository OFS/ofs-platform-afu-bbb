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
// Transform the master TLP vector to a slave vector. The number of elements
// in the two vectors may differ, most often because the master is narrower.
//
// The slave vector guarantees:
//  1. At most one SOP is set. That SOP will always be in slot 0.
//  2. Entries beyond an EOP are empty. (A consequence of #1.)
//  3. All entries up to an EOP or the end of the vector are valid.
//
// Forwarding of the entire vector is delayed until enough
// flits arrive to satisfy #3.
//

module ofs_plat_host_chan_align_axis_tlps
  #(
    parameter NUM_MASTER_TLP_CH = 2,
    parameter NUM_SLAVE_TLP_CH = 2,

    parameter type TDATA_TYPE,
    parameter type TUSER_TYPE
    )
   (
    ofs_plat_axi_stream_if.to_master stream_master,
    ofs_plat_axi_stream_if.to_slave stream_slave
    );

    logic clk;
    assign clk = stream_master.clk;
    logic reset_n;
    assign reset_n = stream_master.reset_n;

    typedef TDATA_TYPE [NUM_MASTER_TLP_CH-1 : 0] t_master_tdata_vec;
    typedef TUSER_TYPE [NUM_MASTER_TLP_CH-1 : 0] t_master_tuser_vec;

    typedef TDATA_TYPE [NUM_SLAVE_TLP_CH-1 : 0] t_slave_tdata_vec;
    typedef TUSER_TYPE [NUM_SLAVE_TLP_CH-1 : 0] t_slave_tuser_vec;


    // ====================================================================
    //
    //  Add a skid buffer on input for timing
    //
    // ====================================================================

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_master_tdata_vec),
        .TUSER_TYPE(t_master_tuser_vec)
        )
      master_skid();

    ofs_plat_axi_stream_if_skid_master_clk entry_skid
       (
        .stream_master(stream_master),
        .stream_slave(master_skid)
        );


    // ====================================================================
    //
    //  Pack TLPs densely at the low end of the vector. It will be easier
    //  to pack TLPs across AXI stream messages if the location of valid
    //  data is well known.
    //
    // ====================================================================

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_master_tdata_vec),
        .TUSER_TYPE(t_master_tuser_vec)
        )
      master_dense();

    assign master_dense.clk = master_skid.clk;
    assign master_dense.reset_n = master_skid.reset_n;
    // Debugging signal
    assign master_dense.instance_number = master_skid.instance_number;

    // Another instance of the interface just to define a t_payload instance
    // for mapping vector entries.
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_master_tdata_vec),
        .TUSER_TYPE(t_master_tuser_vec),
        .DISABLE_CHECKER(1)
        )
      dense_wires();

    logic some_master_slot_valid;
    typedef logic [$clog2(NUM_MASTER_TLP_CH)-1 : 0] t_master_slot_idx;
    t_master_slot_idx dense_mapper[NUM_MASTER_TLP_CH];
    t_master_slot_idx num_master_valid;

    // Generate a mapping from the input to the dense mapping by counting
    // the number of valid entries below each position.
    always_comb
    begin
        some_master_slot_valid = 1'b0;
        num_master_valid = '0;

        for (int i = 0; i < NUM_MASTER_TLP_CH; i = i + 1)
        begin
            // Where should input slot "i" go in the dense mapping?
            dense_mapper[i] = num_master_valid;

            some_master_slot_valid = some_master_slot_valid || master_skid.t.data[i].valid;
            num_master_valid = num_master_valid + t_master_slot_idx'(master_skid.t.data[i].valid);
        end
    end

    // Use the mapping to assign the positions in the dense mapping data vector
    t_master_slot_idx tgt_slot;
    always_comb
    begin
        dense_wires.t = master_skid.t;

        for (int i = 0; i < NUM_MASTER_TLP_CH; i = i + 1)
        begin
            dense_wires.t.data[i].valid = 1'b0;
            dense_wires.t.data[i].sop = 1'b0;
            dense_wires.t.data[i].eop = 1'b0;
        end

        // Push TLPs to the low vector slots
        for (int i = 0; i < NUM_MASTER_TLP_CH; i = i + 1)
        begin
            tgt_slot = dense_mapper[i];

            dense_wires.t.data[tgt_slot] = master_skid.t.data[i];
            dense_wires.t.user[tgt_slot] = master_skid.t.user[i];

            // Guarantee that EOP/SOP are never set for invalid entries
            dense_wires.t.data[tgt_slot].sop = master_skid.t.data[i].sop &&
                                               master_skid.t.data[i].valid;
            dense_wires.t.data[tgt_slot].eop = master_skid.t.data[i].eop &&
                                               master_skid.t.data[i].valid;
        end
    end

    // Write the dense mapping to a register
    ofs_plat_prim_ready_enable_reg
      #(
        .N_DATA_BITS(stream_master.T_PAYLOAD_WIDTH)
        )
      dense
       (
        .clk,
        .reset_n,

        .enable_from_src(master_skid.tvalid && some_master_slot_valid),
        .data_from_src(dense_wires.t),
        .ready_to_src(master_skid.tready),

        .enable_to_dst(master_dense.tvalid),
        .data_to_dst(master_dense.t),
        .ready_from_dst(master_dense.tready)
        );


    // ====================================================================
    //
    //  Transform the master width stream to the slave stream, enforcing the
    //  guarantees listed at the top of the module.
    //
    // ====================================================================

    // Shift register to merge flits channels across multiple AXI stream
    // flits.
    localparam NUM_WORK_TLP_CH = NUM_MASTER_TLP_CH + NUM_SLAVE_TLP_CH - 1;
    // Leave an extra index bit in order to represent one beyond the last slot.
    typedef logic [$clog2(NUM_WORK_TLP_CH) : 0] t_work_ch_idx;

    TDATA_TYPE work_data[NUM_WORK_TLP_CH];
    TUSER_TYPE work_user[NUM_WORK_TLP_CH];

    // valid/eop/sop bits from work_data, mapped to dense vectors
    logic [NUM_WORK_TLP_CH-1 : 0] work_valid;
    logic [NUM_WORK_TLP_CH-1 : 0] work_sop;
    logic [NUM_WORK_TLP_CH-1 : 0] work_eop;

    always_comb
    begin
        for (int i = 0; i < NUM_WORK_TLP_CH; i = i + 1)
        begin
            work_valid[i] = work_data[i].valid;
            work_sop[i] = work_data[i].sop;
            work_eop[i] = work_data[i].eop;
        end
    end

    logic work_full, work_empty;
    // Can't add new flits if the slave portion of the work register is full.
    // Valid channels are packed densely, so only the last entry has to be
    // checked.
    assign work_full = work_valid[NUM_SLAVE_TLP_CH-1];
    assign work_empty = !work_valid[0];

    // The outbound work is "valid" only if the vector is full or a packet
    // is terminated.
    logic work_out_valid, work_out_ready;
    assign work_out_valid = &(work_valid[NUM_SLAVE_TLP_CH-1 : 0]) ||
                            |(work_eop[NUM_SLAVE_TLP_CH-1 : 0]);

    // Mask of outbound entries to forward as a group, terminated by EOP.
    logic [NUM_SLAVE_TLP_CH-1 : 0] work_out_valid_mask;
    t_work_ch_idx work_out_num_valid;

    always_comb
    begin
        work_out_num_valid = t_work_ch_idx'(NUM_SLAVE_TLP_CH);
        for (int i = 0; i < NUM_SLAVE_TLP_CH; i = i + 1)
        begin
            if (!work_valid[i])
            begin
                work_out_num_valid = t_work_ch_idx'(i);
                break;
            end
            else if (work_eop[i])
            begin
                work_out_num_valid = t_work_ch_idx'(i + 1);
                break;
            end
        end

        work_out_valid_mask[0] = work_valid[0];
        for (int i = 1; i < NUM_SLAVE_TLP_CH; i = i + 1)
        begin
            work_out_valid_mask[i] = work_valid[i] && work_out_valid_mask[i-1] &&
                                     !work_eop[i-1];
        end
    end

    // Does the work vector have an SOP entry that isn't in the lowest
    // slot? If so, then even if work_out_ready is true there may not
    // be enough space for incoming values.
    logic work_has_blocking_sop;

    always_comb
    begin
        work_has_blocking_sop = 1'b0;
        for (int i = 1; i < NUM_SLAVE_TLP_CH; i = i + 1)
        begin
            work_has_blocking_sop = work_has_blocking_sop ||
                                    (work_valid[i] && work_sop[i]);
        end
    end

    // Index of the currently first invalid channel in the vector
    t_work_ch_idx work_first_invalid;

    always_comb
    begin
        work_first_invalid = t_work_ch_idx'(NUM_WORK_TLP_CH);
        for (int i = 0; i < NUM_WORK_TLP_CH; i = i + 1)
        begin
            if (!work_valid[i])
            begin
                work_first_invalid = t_work_ch_idx'(i);
                break;
            end
        end
    end

    // Next insertion point, taking into account outbound entries
    t_work_ch_idx next_insertion_idx;
    assign next_insertion_idx =
        work_first_invalid -
        ((work_out_valid & work_out_ready) ? work_out_num_valid : 0);

    //
    // Finally, we are ready to update the work vectors.
    //
    assign master_dense.tready = (!work_full ||
                                  (work_out_ready && !work_has_blocking_sop));

    always_ff @(posedge clk)
    begin
        if (work_out_valid && work_out_ready)
        begin
            // Shift work entries not forwarded this cycle
            for (int i = 0; i < NUM_WORK_TLP_CH; i = i + 1)
            begin
                work_data[i] <= work_data[i + work_out_num_valid];
                work_user[i] <= work_user[i + work_out_num_valid];

                // Clear entries with values shifted out
                if (i >= (NUM_WORK_TLP_CH - work_out_num_valid))
                begin
                    work_data[i].valid <= 1'b0;
                    work_data[i].sop <= 1'b0;
                    work_data[i].eop <= 1'b0;
                end
            end
        end

        // Add new entries
        if (master_dense.tvalid && master_dense.tready)
        begin
            for (int i = 0; i < NUM_MASTER_TLP_CH; i = i + 1)
            begin
                work_data[i + next_insertion_idx] <= master_dense.t.data[i];
                work_user[i + next_insertion_idx] <= master_dense.t.user[i];
            end
        end

        if (!reset_n)
        begin
            for (int i = 0; i < NUM_WORK_TLP_CH; i = i + 1)
            begin
                work_data[i].valid <= 1'b0;
                work_data[i].sop <= 1'b0;
                work_data[i].eop <= 1'b0;
            end
        end
    end

    // Another instance of the interface just to define a t_payload instance
    // for mapping vector entries.
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_slave_tdata_vec),
        .TUSER_TYPE(t_slave_tuser_vec),
        .DISABLE_CHECKER(1)
        )
      work_out_wires();

    // Final mapping of this cycle's work_data/work_user to a stream interface
    always_comb
    begin
        for (int i = 0; i < NUM_SLAVE_TLP_CH; i = i + 1)
        begin
            work_out_wires.t.data[i] = work_data[i];
            work_out_wires.t.data[i].valid = work_data[i].valid && work_out_valid_mask[i];
            work_out_wires.t.data[i].sop = work_data[i].sop && work_out_valid_mask[i];
            work_out_wires.t.data[i].eop = work_data[i].eop && work_out_valid_mask[i];

            work_out_wires.t.user[i] = work_user[i];
        end
    end

    assign work_out_wires.t.last = 1'b0;

    ofs_plat_prim_ready_enable_reg
      #(
        .N_DATA_BITS(stream_slave.T_PAYLOAD_WIDTH)
        )
      to_slave
       (
        .clk,
        .reset_n,

        .enable_from_src(work_out_valid),
        .data_from_src(work_out_wires.t),
        .ready_to_src(work_out_ready),

        .enable_to_dst(stream_slave.tvalid),
        .data_to_dst(stream_slave.t),
        .ready_from_dst(stream_slave.tready)
        );

endmodule // ofs_plat_host_chan_align_axis_tlps
