// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Map an AXI port to the properties required a host memory port. Maximum
// burst size, alignment and response ordering are all handled here.
// The sink remains in AXI format. The final, protocol-specific, host
// port conversion is handled outside this module.
//
module ofs_plat_map_axi_mem_if_to_host_mem
  #(
    // When non-zero the source and sink use different clocks.
    parameter ADD_CLOCK_CROSSING = 0,

    // Sort responses? This is enabled by default because packets
    // may be split due to alignment. Responses from split packets must
    // be recombined in order to avoid violating AXI ordering rules.
    // Some PCIe subsystems sort responses internally, making reordering
    // here unnecessary.
    parameter SORT_RESPONSES = 1,

    // Should the PIM guarantee that every outstanding read response
    // has a buffer slot inside the PIM? When a ROB is needed to sort
    // responses this property is guaranteed. When responses are already
    // sorted, there is no default buffering inside the PIM. Some AFUs
    // depend on a buffer to avoid deadlocks. For example, an AFU that
    // routes read responses back as writes can deadlock if the read
    // and write request channels have shared control logic. In that case,
    // backed up read responses may inibit writes, thus deadlocking.
    // Setting BUFFER_READ_RESPONSES guarantees a home for all read
    // responses inside the PIM.
    //
    // This parameter is ignored when responses are sorted, since the
    // ROB provides a buffer.
    parameter BUFFER_READ_RESPONSES = 0,

    // Does the host memory port require natural alignment?
    parameter NATURAL_ALIGNMENT = 0,

    // Does the host memory port require avoiding page crossing?
    parameter PAGE_SIZE = 0,

    // Sizes of the response buffers in the ROB and clock crossing.
    parameter MAX_ACTIVE_RD_LINES = 256,
    parameter MAX_ACTIVE_WR_LINES = 256,

    // When non-zero, the write channel is blocked when the read channel runs
    // out of credits. On some channels, such as PCIe TLP, blocking writes along
    // with reads solves a fairness problem caused by writes not having either
    // tags or completions.
    parameter BLOCK_WRITE_WITH_READ = 0,

    parameter NUM_PAYLOAD_RCB_SEGS = 1
    )
   (
    // mem_source parameters should match the source's field widths.
    ofs_plat_axi_mem_if.to_source mem_source,

    // mem_sink parameters should match the requirements of the host
    // memory port. The RID and WID fields should be sized to hold reorder
    // buffer indices for read and write responses.
    ofs_plat_axi_mem_if.to_sink mem_sink
    );

    //
    // Fork atomic update requests into two requests: the original on the write
    // request channel and a copy on the read request channel. The read request
    // copy is just a placeholder, used to allocate ROB slots and tags internal
    // to the PIM. These slots will be used when passing the read response from
    // the atomic update back to the AFU.
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_source)
        )
      axi_fiu_atomic_if();

    assign axi_fiu_atomic_if.clk = mem_source.clk;
    assign axi_fiu_atomic_if.reset_n = mem_source.reset_n;
    assign axi_fiu_atomic_if.instance_number = mem_sink.instance_number;

    ofs_plat_axi_mem_if_fork_atomics fork_atomics
       (
        .mem_source,
        .mem_sink(axi_fiu_atomic_if)
        );


    //
    // Map AFU-sized bursts to FIU-sized bursts. (The AFU may generate larger
    // bursts than the FIU will accept.)
    //
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_MEM_PARAMS(mem_source),
        .BURST_CNT_WIDTH(mem_sink.BURST_CNT_WIDTH),
        .RID_WIDTH(mem_source.RID_WIDTH),
        .WID_WIDTH(mem_source.WID_WIDTH),
        .USER_WIDTH(mem_source.USER_WIDTH)
        )
      axi_fiu_burst_if();

    assign axi_fiu_burst_if.clk = mem_source.clk;
    assign axi_fiu_burst_if.reset_n = mem_source.reset_n;
    assign axi_fiu_burst_if.instance_number = mem_sink.instance_number;

    ofs_plat_axi_mem_if_map_bursts
      #(
        .UFLAG_NO_REPLY(ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_NO_REPLY),
        .NATURAL_ALIGNMENT(NATURAL_ALIGNMENT),
        .PAGE_SIZE(PAGE_SIZE)
        )
      map_bursts
       (
        .mem_source(axi_fiu_atomic_if),
        .mem_sink(axi_fiu_burst_if)
        );


    //
    // If responses are already sorted then no reorder buffer is needed here.
    //
    generate
        if (SORT_RESPONSES)
        begin : s
            //
            // Protect the read and write response buffers from overflow by tracking
            // buffer credits. The memory driver in the FIM has no flow control.
            //
            ofs_plat_axi_mem_if
              #(
                `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(axi_fiu_burst_if)
                )
              axi_fiu_credit_if();

            assign axi_fiu_credit_if.clk = mem_source.clk;
            assign axi_fiu_credit_if.reset_n = mem_source.reset_n;
            assign axi_fiu_credit_if.instance_number = mem_sink.instance_number;

            ofs_plat_axi_mem_if_rsp_credits
              #(
                .NUM_READ_CREDITS(MAX_ACTIVE_RD_LINES),
                .NUM_WRITE_CREDITS(MAX_ACTIVE_WR_LINES),
                .BLOCK_WRITE_WITH_READ(BLOCK_WRITE_WITH_READ)
                )
              rsp_credits
               (
                .mem_source(axi_fiu_burst_if),
                .mem_sink(axi_fiu_credit_if)
                );

            //
            // Cross to the FIU clock and add sort responses. The two are combined
            // because the clock crossing buffer can also be used for sorting.
            //
            ofs_plat_axi_mem_if_async_rob
              #(
                .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
                .NUM_READ_CREDITS(MAX_ACTIVE_RD_LINES),
                .NUM_WRITE_CREDITS(MAX_ACTIVE_WR_LINES),
                .NUM_PAYLOAD_RCB_SEGS(NUM_PAYLOAD_RCB_SEGS)
                )
              rob
               (
                .mem_source(axi_fiu_credit_if),
                .mem_sink
                );
        end
        else
        begin : ns
            //
            // No sorting is required, but a clock crossing may be needed.
            // In addition, AFU-side user fields and parts of the ID field not
            // returned by the FIM must also be preserved.
            //
            ofs_plat_axi_mem_if
              #(
                `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(axi_fiu_burst_if)
                )
              axi_fiu_clk_if();

            assign axi_fiu_clk_if.clk = mem_sink.clk;
            assign axi_fiu_clk_if.reset_n = mem_sink.reset_n;
            assign axi_fiu_clk_if.instance_number = mem_sink.instance_number;

            if (ADD_CLOCK_CROSSING)
            begin
                ofs_plat_axi_mem_if_async_shim
                  #(
                    .ADD_TIMING_REG_STAGES(1),
                    .NUM_READ_CREDITS(16),
                    .NUM_WRITE_CREDITS(16)
                    )
                  to_fiu_clk
                   (
                    .mem_source(axi_fiu_burst_if),
                    .mem_sink(axi_fiu_clk_if)
                    );
            end
            else
            begin
                ofs_plat_axi_mem_if_connect conn_clk
                   (
                    .mem_source(axi_fiu_burst_if),
                    .mem_sink(axi_fiu_clk_if)
                    );
            end


            //
            // Responses are already sorted. Just record the metadata (full ID
            // and USER fields) that may not be preserved in completions.
            //
            ofs_plat_axi_mem_if
              #(
                `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(mem_sink)
                )
              axi_fiu_buf_if();

            assign axi_fiu_buf_if.clk = mem_sink.clk;
            assign axi_fiu_buf_if.reset_n = mem_sink.reset_n;
            assign axi_fiu_buf_if.instance_number = mem_sink.instance_number;

            ofs_plat_axi_mem_if_preserve_meta
              #(
                // There is one entry per packet, not per line, so limit
                // the size of the tracking logic.
                .NUM_READ_CREDITS(MAX_ACTIVE_RD_LINES > 512 ? 512 : MAX_ACTIVE_RD_LINES),
                .NUM_WRITE_CREDITS(MAX_ACTIVE_WR_LINES > 512 ? 512 : MAX_ACTIVE_WR_LINES)
                )
              preserve_meta
               (
                .mem_source(axi_fiu_clk_if),
                .mem_sink(axi_fiu_buf_if)
                );


            //
            // There is no ROB because responses are already sorted.
            // Is a FIFO buffer requested by the AFU?
            //
            if (BUFFER_READ_RESPONSES)
            begin
                // Provide a home for every active read response.
                ofs_plat_axi_mem_if_buffered_read
                  #(
                    .NUM_READ_ENTRIES(MAX_ACTIVE_RD_LINES)
                    )
                  to_fiu_buf
                   (
                    .mem_source(axi_fiu_buf_if),
                    .mem_sink
                    );
            end
            else
            begin
                ofs_plat_axi_mem_if_connect conn_buf
                   (
                    .mem_source(axi_fiu_buf_if),
                    .mem_sink
                    );
            end
        end
    endgenerate


    // synthesis translate_off
    always_ff @(negedge mem_source.clk)
    begin
        if (mem_source.reset_n)
        begin
            if (mem_source.awvalid && mem_source.awready)
            begin
                // Memory fence?
                if ((mem_source.USER_WIDTH > ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_FENCE) &&
                    mem_source.aw.user[ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_FENCE])
                begin
                    if (mem_source.aw.len)
                    begin
                        $fatal(2, "** ERROR ** %m: Memory fence AWLEN must be 0!");
                    end
                end
            end
        end
    end
    // synthesis translate_on

endmodule // ofs_plat_map_axi_mem_if_to_host_mem
