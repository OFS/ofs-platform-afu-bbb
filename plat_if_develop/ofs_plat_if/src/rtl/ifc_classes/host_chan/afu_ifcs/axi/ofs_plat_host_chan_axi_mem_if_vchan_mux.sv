// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Break a multiplexed host channel memory interface into separate ports.
// This is the equivalent of the FIM's PF/VF MUX, but operating on
// AXI-MM.
//
// Virtual channel tags are defined in
// ofs_plat_host_chan_axi_mem_pkg::t_hc_axi_user_vchan.
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_axi_mem_if_vchan_mux
  #(
    parameter NUM_AFU_PORTS = 1,

    // Add pipeline registers to host_mem inputs. Registers are always
    // added to host_mem outputs. Off by default because host_mem is
    // typically fed from the PIM, which already has registers.
    parameter REGISTER_HOST_MEM = 0,

    // Add pipeline registers to afu_mem inputs. Registers are always
    // added to afu_mem outputs.
    parameter REGISTER_AFU_MEM = 1
    )
   (
    ofs_plat_axi_mem_if.to_sink host_mem,
    ofs_plat_axi_mem_if.to_source afu_mem[NUM_AFU_PORTS]
    );

    wire clk = host_mem.clk;
    wire reset_n = host_mem.reset_n;

    localparam T_AR_WIDTH = host_mem.T_AR_WIDTH;
    localparam T_R_WIDTH = host_mem.T_R_WIDTH;

    localparam T_AW_WIDTH = host_mem.T_AW_WIDTH;
    localparam T_W_WIDTH = host_mem.T_W_WIDTH;
    localparam T_FULL_W_WIDTH = T_AW_WIDTH + T_W_WIDTH;
    localparam T_B_WIDTH = host_mem.T_B_WIDTH;

    typedef logic [T_AR_WIDTH-1 : 0] t_ar_payload;
    typedef logic [T_R_WIDTH-1 : 0] t_r_payload;

    typedef logic [T_FULL_W_WIDTH-1 : 0] t_full_w_payload;
    typedef logic [T_B_WIDTH-1 : 0] t_b_payload;

    typedef logic [$clog2(NUM_AFU_PORTS)-1 : 0] t_vchan_num;

    if (NUM_AFU_PORTS == 1)
    begin : c
        // Simple 1:1 mapping
        ofs_plat_axi_mem_if_connect conn
           (
            .mem_sink(host_mem),
            .mem_source(afu_mem[0])
            );
    end
    else
    begin : m
        ofs_plat_axi_mem_if
          #(
            `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(host_mem)
            )
          host_mem_skid();

        assign host_mem_skid.clk = clk;
        assign host_mem_skid.reset_n = reset_n;
        assign host_mem_skid.instance_number = host_mem.instance_number;

        ofs_plat_axi_mem_if_skid
          #(
            .SKID_AW(0),
            .SKID_W(0),
            .SKID_B(REGISTER_HOST_MEM),
            .SKID_AR(0),
            .SKID_R(REGISTER_HOST_MEM)
            )
          skid
           (
            .mem_sink(host_mem),
            .mem_source(host_mem_skid)
            );

        ofs_plat_axi_mem_if
          #(
            // Use host_mem for parameters. They have already been confirmed
            // identical to afu_mem. Some tools have trouble extracting
            // parameters from a vector of interfaces.
            `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(host_mem)
            )
          afu_mem_skid[NUM_AFU_PORTS]();

        for (genvar p = 0; p < NUM_AFU_PORTS; p = p + 1) begin : s
            assign afu_mem_skid[p].clk = clk;
            assign afu_mem_skid[p].reset_n = reset_n;
            assign afu_mem_skid[p].instance_number = afu_mem[p].instance_number;

            ofs_plat_axi_mem_if_skid
              #(
                .SKID_AW(REGISTER_AFU_MEM),
                .SKID_W(REGISTER_AFU_MEM),
                .SKID_B(0),
                .SKID_AR(REGISTER_AFU_MEM),
                .SKID_R(0)
                )
              skid
               (
                .mem_source(afu_mem[p]),
                .mem_sink(afu_mem_skid[p])
                );
        end

        // ====================================================================
        //
        //  Reads
        //
        // ====================================================================

        // Encapsulate read requests and responses in AXI streams.
        // The MUX primitive operates on opaque AXI-S interfaces, passing
        // tdata through the MUX with tuser as the port selector.
        ofs_plat_axi_stream_if #(.TDATA_TYPE(t_ar_payload), .TUSER_TYPE(logic))
            host_str_ar();
        // tuser is unused on the MUX output side
        ofs_plat_axi_stream_if #(.TDATA_TYPE(t_ar_payload), .TUSER_TYPE(logic))
            afu_str_ar[NUM_AFU_PORTS]();

        // R is the stream routed by vchan: mux -> demux
        ofs_plat_axi_stream_if #(.TDATA_TYPE(t_r_payload), .TUSER_TYPE(t_vchan_num))
            host_str_r();
        // tuser is unused on the MUX output side
        ofs_plat_axi_stream_if #(.TDATA_TYPE(t_r_payload), .TUSER_TYPE(logic))
            afu_str_r[NUM_AFU_PORTS]();

        assign host_str_ar.clk = clk;
        assign host_str_ar.reset_n = reset_n;
        assign host_str_ar.instance_number = 0;

        assign host_str_r.clk = clk;
        assign host_str_r.reset_n = reset_n;
        assign host_str_r.instance_number = 0;

        for (genvar p = 0; p < NUM_AFU_PORTS; p = p + 1) begin
            assign afu_str_ar[p].clk = clk;
            assign afu_str_ar[p].reset_n = reset_n;
            assign afu_str_ar[p].instance_number = p;

            assign afu_str_r[p].clk = clk;
            assign afu_str_r[p].reset_n = reset_n;
            assign afu_str_r[p].instance_number = p;
        end

        assign host_str_r.tvalid = host_mem_skid.rvalid;
        assign host_mem_skid.rready = host_str_r.tready;

        ofs_plat_host_chan_axi_mem_pkg::t_hc_axi_user_flags_with_vchan r_user_flags;
        assign r_user_flags = ofs_plat_host_chan_axi_mem_pkg::t_hc_axi_user_flags_with_vchan'(host_mem_skid.r.user);

        always_comb begin
            host_str_r.t = '0;
            host_str_r.t.data = host_mem_skid.r;
            host_str_r.t.last = host_mem_skid.r.last;

            // Pass the demultiplexed port ID in tuser
            host_str_r.t.user = t_vchan_num'(r_user_flags.vchan);
        end

        assign host_mem_skid.arvalid = host_str_ar.tvalid;
        assign host_str_ar.tready = host_mem_skid.arready;
        assign host_mem_skid.ar = host_str_ar.t.data;

        for (genvar p = 0; p < NUM_AFU_PORTS; p = p + 1) begin
            assign afu_mem_skid[p].rvalid = afu_str_r[p].tvalid;
            assign afu_str_r[p].tready = afu_mem_skid[p].rready;
            assign afu_mem_skid[p].r = afu_str_r[p].t.data;

            assign afu_str_ar[p].tvalid = afu_mem_skid[p].arvalid;
            assign afu_mem_skid[p].arready = afu_str_ar[p].tready;
            always_comb begin
                afu_str_ar[p].t = '0;
                afu_str_ar[p].t.data = afu_mem_skid[p].ar;
                // AR is never a burst
                afu_str_ar[p].t.last = 1'b1;
            end
        end

        ofs_plat_prim_vchan_mux
          #(
            .NUM_DEMUX_PORTS(NUM_AFU_PORTS)
            )
          r_mux
           (
            .demux_in(afu_str_ar),
            .mux_out(host_str_ar)
            );

        ofs_plat_prim_vchan_demux
          #(
            .NUM_DEMUX_PORTS(NUM_AFU_PORTS)
            )
          r_demux
           (
            .mux_in(host_str_r),
            .demux_out(afu_str_r)
            );


        // ====================================================================
        //
        //  Writes
        //
        // ====================================================================

        // Combine AW and W into a single stream. AXI-Lite has no bursts,
        // so there is always one W for every AW.
        ofs_plat_axi_stream_if #(.TDATA_TYPE(t_full_w_payload), .TUSER_TYPE(logic))
            host_str_w();
        // tuser is unused on the MUX output side
        ofs_plat_axi_stream_if #(.TDATA_TYPE(t_full_w_payload), .TUSER_TYPE(logic))
            afu_str_w[NUM_AFU_PORTS]();

        // B is the stream routed by vchan: mux -> demux
        ofs_plat_axi_stream_if #(.TDATA_TYPE(t_b_payload), .TUSER_TYPE(t_vchan_num))
            host_str_b();
        // tuser is unused on the MUX output side
        ofs_plat_axi_stream_if #(.TDATA_TYPE(t_b_payload), .TUSER_TYPE(logic))
            afu_str_b[NUM_AFU_PORTS]();

        assign host_str_w.clk = clk;
        assign host_str_w.reset_n = reset_n;
        assign host_str_w.instance_number = 0;

        assign host_str_b.clk = clk;
        assign host_str_b.reset_n = reset_n;
        assign host_str_b.instance_number = 0;

        for (genvar p = 0; p < NUM_AFU_PORTS; p = p + 1) begin
            assign afu_str_w[p].clk = clk;
            assign afu_str_w[p].reset_n = reset_n;
            assign afu_str_w[p].instance_number = p;

            assign afu_str_b[p].clk = clk;
            assign afu_str_b[p].reset_n = reset_n;
            assign afu_str_b[p].instance_number = p;
        end


        // Manage split ready/enable on AW/W output. AW is present only on write
        // SOP cycles.
        logic did_aw;
        logic did_w;
        logic host_mem_skid_w_sop;

        assign host_mem_skid.awvalid = host_str_w.tvalid && !did_aw && host_mem_skid_w_sop;
        assign host_mem_skid.wvalid = host_str_w.tvalid && !did_w;
        assign host_str_w.tready = (host_mem_skid.awready || did_aw || !host_mem_skid_w_sop) &&
                                   (host_mem_skid.wready || did_w);
        assign { host_mem_skid.w, host_mem_skid.aw } = host_str_w.t.data;

        always_ff @(posedge clk) begin
            if (host_mem_skid.awvalid && host_mem_skid.awready)
                did_aw <= 1'b1;
            if (host_mem_skid.wvalid && host_mem_skid.wready)
                did_w <= 1'b1;

            if (host_str_w.tvalid && host_str_w.tready) begin
                did_aw <= 1'b0;
                did_w <= 1'b0;
                host_mem_skid_w_sop <= host_mem_skid.w.last;
            end

            if (!reset_n) begin
                did_aw <= 1'b0;
                did_w <= 1'b0;
                host_mem_skid_w_sop <= 1'b1;
            end
        end

        ofs_plat_host_chan_axi_mem_pkg::t_hc_axi_user_flags_with_vchan b_user_flags;
        assign b_user_flags = ofs_plat_host_chan_axi_mem_pkg::t_hc_axi_user_flags_with_vchan'(host_mem_skid.b.user);

        assign host_str_b.tvalid = host_mem_skid.bvalid;
        assign host_mem_skid.bready = host_str_b.tready;
        always_comb begin
            host_str_b.t = '0;
            host_str_b.t.data = host_mem_skid.b;
            host_str_b.t.last = 1'b1;

            // Pass the demultiplexed port ID in tuser
            host_str_b.t.user = t_vchan_num'(b_user_flags.vchan);
        end


        logic host_mem_w_sop[NUM_AFU_PORTS];

        for (genvar p = 0; p < NUM_AFU_PORTS; p = p + 1) begin
            assign afu_str_w[p].tvalid = afu_mem_skid[p].wvalid && (afu_mem_skid[p].awvalid || !host_mem_w_sop[p]);
            assign afu_mem_skid[p].awready = afu_str_w[p].tready && afu_mem_skid[p].wvalid && host_mem_w_sop[p];
            assign afu_mem_skid[p].wready = afu_str_w[p].tready && (afu_mem_skid[p].awvalid || !host_mem_w_sop[p]);

            always_comb begin
                afu_str_w[p].t = '0;
                afu_str_w[p].t.data = { afu_mem_skid[p].w, (host_mem_w_sop[p] ? afu_mem_skid[p].aw : {T_AW_WIDTH{1'b0}}) };
                afu_str_w[p].t.last = afu_mem_skid[p].w.last;
            end

            always_ff @(posedge clk) begin
                if (afu_mem_skid[p].wvalid && afu_mem_skid[p].wready)
                    host_mem_w_sop[p] <= afu_mem_skid[p].w.last;

                if (!reset_n)
                    host_mem_w_sop[p] <= 1'b1;
            end

            assign afu_mem_skid[p].bvalid = afu_str_b[p].tvalid;
            assign afu_str_b[p].tready = afu_mem_skid[p].bready;
            assign afu_mem_skid[p].b = afu_str_b[p].t.data;
        end


        ofs_plat_prim_vchan_mux
          #(
            .NUM_DEMUX_PORTS(NUM_AFU_PORTS)
            )
          w_mux
           (
            .demux_in(afu_str_w),
            .mux_out(host_str_w)
            );

        ofs_plat_prim_vchan_demux
          #(
            .NUM_DEMUX_PORTS(NUM_AFU_PORTS)
            )
          w_demux
           (
            .mux_in(host_str_b),
            .demux_out(afu_str_b)
            );

    end // else: !if(NUM_AFU_PORTS == 1)


    // ====================================================================
    //
    //  Validation
    //
    // ====================================================================

    // synthesis translate_off
    initial
    begin
        if (T_AR_WIDTH != afu_mem[0].T_AR_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: Parameter/size mismatch: host %0d, AFU %0d!",
                   T_AR_WIDTH, afu_mem[0].T_AR_WIDTH);
        end
        if (T_R_WIDTH != afu_mem[0].T_R_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: Parameter/size mismatch: host %0d, AFU %0d!",
                   T_R_WIDTH, afu_mem[0].T_R_WIDTH);
        end

        if (T_AW_WIDTH != afu_mem[0].T_AW_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: Parameter/size mismatch: host %0d, AFU %0d!",
                   T_AW_WIDTH, afu_mem[0].T_AW_WIDTH);
        end
        if (T_W_WIDTH != afu_mem[0].T_W_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: Parameter/size mismatch: host %0d, AFU %0d!",
                   T_W_WIDTH, afu_mem[0].T_W_WIDTH);
        end
        if (T_B_WIDTH != afu_mem[0].T_B_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: Parameter/size mismatch: host %0d, AFU %0d!",
                   T_B_WIDTH, afu_mem[0].T_B_WIDTH);
        end

        if (host_mem.USER_WIDTH < $bits(ofs_plat_host_chan_axi_mem_pkg::t_hc_axi_user_vchan))
        begin
            $fatal(2, "** ERROR ** %m: USER_WIDTH (%0d) is too small for virtual channel tag (%0d)!",
                   host_mem.USER_WIDTH, $bits(ofs_plat_host_chan_axi_mem_pkg::t_hc_axi_user_vchan));
        end
    end
    // synthesis translate_on

endmodule // ofs_plat_host_chan_axi_mem_if_vchan_mux
