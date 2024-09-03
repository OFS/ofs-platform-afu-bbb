// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Break a multiplexed host channel MMIO interface into separate ports.
// This is the equivalent of the FIM's PF/VF MUX, but operating on
// AXI-Lite.
//
// Virtual channel tags are defined in
// ofs_plat_host_chan_axi_mem_pkg::t_hc_axi_user_vchan.
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_axi_mem_lite_if_vchan_mux
  #(
    parameter NUM_AFU_PORTS = 1,

    // Add pipeline registers to host_mmio inputs. Registers are always
    // added to host_mmio outputs. Off by default because host_mmio is
    // typically fed from the PIM, which already has registers.
    parameter REGISTER_HOST_MMIO = 0,

    // Add pipeline registers to afu_mmio inputs. Registers are always
    // added to afu_mmio outputs.
    parameter REGISTER_AFU_MMIO = 1
    )
   (
    ofs_plat_axi_mem_lite_if.to_source host_mmio,
    ofs_plat_axi_mem_lite_if.to_sink afu_mmio[NUM_AFU_PORTS]
    );

    wire clk = host_mmio.clk;
    wire reset_n = host_mmio.reset_n;

    localparam T_AR_WIDTH = host_mmio.T_AR_WIDTH;
    localparam T_R_WIDTH = host_mmio.T_R_WIDTH;

    localparam T_AW_WIDTH = host_mmio.T_AW_WIDTH;
    localparam T_W_WIDTH = host_mmio.T_W_WIDTH;
    localparam T_FULL_W_WIDTH = T_AW_WIDTH + T_W_WIDTH;
    localparam T_B_WIDTH = host_mmio.T_B_WIDTH;

    typedef logic [T_AR_WIDTH-1 : 0] t_ar_payload;
    typedef logic [T_R_WIDTH-1 : 0] t_r_payload;

    typedef logic [T_FULL_W_WIDTH-1 : 0] t_full_w_payload;
    typedef logic [T_B_WIDTH-1 : 0] t_b_payload;

    typedef logic [$clog2(NUM_AFU_PORTS)-1 : 0] t_vchan_num;

    if (NUM_AFU_PORTS == 1)
    begin : c
        // Simple 1:1 mapping
        ofs_plat_axi_mem_lite_if_connect conn
           (
            .mem_source(host_mmio),
            .mem_sink(afu_mmio[0])
            );
    end
    else
    begin : m
        ofs_plat_axi_mem_lite_if
          #(
            `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(host_mmio)
            )
          host_mmio_skid();

        assign host_mmio_skid.clk = clk;
        assign host_mmio_skid.reset_n = reset_n;
        assign host_mmio_skid.instance_number = host_mmio.instance_number;

        ofs_plat_axi_mem_lite_if_skid
          #(
            .SKID_AW(REGISTER_HOST_MMIO),
            .SKID_W(REGISTER_HOST_MMIO),
            .SKID_B(0),
            .SKID_AR(REGISTER_HOST_MMIO),
            .SKID_R(0)
            )
          skid
           (
            .mem_source(host_mmio),
            .mem_sink(host_mmio_skid)
            );

        ofs_plat_axi_mem_lite_if
          #(
            // Use host_mmio for parameters. They have already been confirmed
            // identical to afu_mmio. Some tools have trouble extracting
            // parameters from a vector of interfaces.
            `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(host_mmio)
            )
          afu_mmio_skid[NUM_AFU_PORTS]();

        for (genvar p = 0; p < NUM_AFU_PORTS; p = p + 1) begin : s
            assign afu_mmio_skid[p].clk = clk;
            assign afu_mmio_skid[p].reset_n = reset_n;
            assign afu_mmio_skid[p].instance_number = afu_mmio[p].instance_number;

            ofs_plat_axi_mem_lite_if_skid
              #(
                .SKID_AW(0),
                .SKID_W(0),
                .SKID_B(REGISTER_AFU_MMIO),
                .SKID_AR(0),
                .SKID_R(REGISTER_AFU_MMIO)
                )
              skid
               (
                .mem_sink(afu_mmio[p]),
                .mem_source(afu_mmio_skid[p])
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
        ofs_plat_axi_stream_if #(.TDATA_TYPE(t_ar_payload), .TUSER_TYPE(t_vchan_num))
            host_str_ar();
        // tuser is unused on the MUX output side
        ofs_plat_axi_stream_if #(.TDATA_TYPE(t_ar_payload), .TUSER_TYPE(logic))
            afu_str_ar[NUM_AFU_PORTS]();

        ofs_plat_axi_stream_if #(.TDATA_TYPE(t_r_payload), .TUSER_TYPE(logic))
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

        assign host_str_ar.tvalid = host_mmio_skid.arvalid;
        assign host_mmio_skid.arready = host_str_ar.tready;

        ofs_plat_host_chan_axi_mem_pkg::t_hc_axi_mmio_user_flags_with_vchan ar_user_flags;
        assign ar_user_flags = ofs_plat_host_chan_axi_mem_pkg::t_hc_axi_mmio_user_flags_with_vchan'(host_mmio_skid.ar.user);

        always_comb begin
            host_str_ar.t = '0;
            host_str_ar.t.data = host_mmio_skid.ar;
            // AR is never a burst
            host_str_ar.t.last = 1'b1;

            // Pass the demultiplexed port ID in tuser
            host_str_ar.t.user = t_vchan_num'(ar_user_flags.vchan);
        end

        assign host_mmio_skid.rvalid = host_str_r.tvalid;
        assign host_str_r.tready = host_mmio_skid.rready;
        assign host_mmio_skid.r = host_str_r.t.data;

        for (genvar p = 0; p < NUM_AFU_PORTS; p = p + 1) begin
            assign afu_mmio_skid[p].arvalid = afu_str_ar[p].tvalid;
            assign afu_str_ar[p].tready = afu_mmio_skid[p].arready;
            assign afu_mmio_skid[p].ar = afu_str_ar[p].t.data;

            assign afu_str_r[p].tvalid = afu_mmio_skid[p].rvalid;
            assign afu_mmio_skid[p].rready = afu_str_r[p].tready;
            always_comb begin
                afu_str_r[p].t = '0;
                afu_str_r[p].t.data = afu_mmio_skid[p].r;
                // AXI-Lite has no bursts
                afu_str_r[p].t.last = 1'b1;
            end
        end

        ofs_plat_prim_vchan_mux
          #(
            .NUM_DEMUX_PORTS(NUM_AFU_PORTS)
            )
          r_mux
           (
            .demux_in(afu_str_r),
            .mux_out(host_str_r)
            );

        ofs_plat_prim_vchan_demux
          #(
            .NUM_DEMUX_PORTS(NUM_AFU_PORTS)
            )
          r_demux
           (
            .mux_in(host_str_ar),
            .demux_out(afu_str_ar)
            );


        // ====================================================================
        //
        //  Writes
        //
        // ====================================================================

        // Combine AW and W into a single stream. AXI-Lite has no bursts,
        // so there is always one W for every AW.
        ofs_plat_axi_stream_if #(.TDATA_TYPE(t_full_w_payload), .TUSER_TYPE(t_vchan_num))
            host_str_w();
        // tuser is unused on the MUX output side
        ofs_plat_axi_stream_if #(.TDATA_TYPE(t_full_w_payload), .TUSER_TYPE(logic))
            afu_str_w[NUM_AFU_PORTS]();

        ofs_plat_axi_stream_if #(.TDATA_TYPE(t_b_payload), .TUSER_TYPE(logic))
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

        assign host_str_w.tvalid = host_mmio_skid.wvalid && host_mmio_skid.awvalid;
        assign host_mmio_skid.awready = host_str_w.tready && host_mmio_skid.wvalid;
        assign host_mmio_skid.wready = host_str_w.tready && host_mmio_skid.awvalid;

        ofs_plat_host_chan_axi_mem_pkg::t_hc_axi_mmio_user_flags_with_vchan aw_user_flags;
        assign aw_user_flags = ofs_plat_host_chan_axi_mem_pkg::t_hc_axi_mmio_user_flags_with_vchan'(host_mmio_skid.aw.user);

        always_comb begin
            host_str_w.t = '0;
            host_str_w.t.data = { host_mmio_skid.w, host_mmio_skid.aw };
            // AXI-Lite has no multi-cycle bursts
            host_str_w.t.last = 1'b1;

            // Pass the demultiplexed port ID in tuser
            host_str_w.t.user = t_vchan_num'(aw_user_flags.vchan);
        end

        assign host_mmio_skid.bvalid = host_str_b.tvalid;
        assign host_str_b.tready = host_mmio_skid.bready;
        assign host_mmio_skid.b = host_str_b.t.data;

        // Manage split ready/enable on AW/W output
        logic did_aw[NUM_AFU_PORTS];
        logic did_w[NUM_AFU_PORTS];

        for (genvar p = 0; p < NUM_AFU_PORTS; p = p + 1) begin
            assign afu_mmio_skid[p].awvalid = afu_str_w[p].tvalid && !did_aw[p];
            assign afu_mmio_skid[p].wvalid = afu_str_w[p].tvalid && !did_w[p];
            assign afu_str_w[p].tready = (afu_mmio_skid[p].awready || did_aw[p]) &&
                                         (afu_mmio_skid[p].wready || did_w[p]);
            assign { afu_mmio_skid[p].w, afu_mmio_skid[p].aw } = afu_str_w[p].t.data;

            always_ff @(posedge clk) begin
                if (afu_mmio_skid[p].awvalid && afu_mmio_skid[p].awready)
                    did_aw[p] <= 1'b1;
                if (afu_mmio_skid[p].wvalid && afu_mmio_skid[p].wready)
                    did_w[p] <= 1'b1;

                if (!reset_n || afu_str_w[p].tready) begin
                    did_aw[p] <= 1'b0;
                    did_w[p] <= 1'b0;
                end
            end

            assign afu_str_b[p].tvalid = afu_mmio_skid[p].bvalid;
            assign afu_mmio_skid[p].bready = afu_str_b[p].tready;
            always_comb begin
                afu_str_b[p].t = '0;
                afu_str_b[p].t.data = afu_mmio_skid[p].b;
                afu_str_b[p].t.last = 1'b1;
            end
        end

        ofs_plat_prim_vchan_mux
          #(
            .NUM_DEMUX_PORTS(NUM_AFU_PORTS)
            )
          w_mux
           (
            .demux_in(afu_str_b),
            .mux_out(host_str_b)
            );

        ofs_plat_prim_vchan_demux
          #(
            .NUM_DEMUX_PORTS(NUM_AFU_PORTS)
            )
          w_demux
           (
            .mux_in(host_str_w),
            .demux_out(afu_str_w)
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
        if (T_AR_WIDTH != afu_mmio[0].T_AR_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: Parameter/size mismatch: host %0d, AFU %0d!",
                   T_AR_WIDTH, afu_mmio[0].T_AR_WIDTH);
        end
        if (T_R_WIDTH != afu_mmio[0].T_R_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: Parameter/size mismatch: host %0d, AFU %0d!",
                   T_R_WIDTH, afu_mmio[0].T_R_WIDTH);
        end

        if (T_AW_WIDTH != afu_mmio[0].T_AW_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: Parameter/size mismatch: host %0d, AFU %0d!",
                   T_AW_WIDTH, afu_mmio[0].T_AW_WIDTH);
        end
        if (T_W_WIDTH != afu_mmio[0].T_W_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: Parameter/size mismatch: host %0d, AFU %0d!",
                   T_W_WIDTH, afu_mmio[0].T_W_WIDTH);
        end
        if (T_B_WIDTH != afu_mmio[0].T_B_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: Parameter/size mismatch: host %0d, AFU %0d!",
                   T_B_WIDTH, afu_mmio[0].T_B_WIDTH);
        end

        if (host_mmio.USER_WIDTH < $bits(ofs_plat_host_chan_axi_mem_pkg::t_hc_axi_user_vchan))
        begin
            $fatal(2, "** ERROR ** %m: USER_WIDTH (%0d) is too small for virtual channel tag (%0d)!",
                   host_mmio.USER_WIDTH, $bits(ofs_plat_host_chan_axi_mem_pkg::t_hc_axi_user_vchan));
        end
    end
    // synthesis translate_on

endmodule // ofs_plat_host_chan_axi_mem_lite_if_vchan_mux
