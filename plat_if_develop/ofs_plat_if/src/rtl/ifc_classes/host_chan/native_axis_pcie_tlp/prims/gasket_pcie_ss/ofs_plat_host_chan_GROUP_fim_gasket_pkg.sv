// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// This gasket maps the PIM's internal PCIe TLP representation to the PCIe
// subsystem in the FIM. Each supported flavor of FIM has a gasket.
//
// Each gasket implementation provides some common parameters and types
// that will be consumed by the platform-independent PIM TLP mapping code.
// The gasket often sets these parameters by importing values from the
// FIM.
//

`include "ofs_plat_if.vh"
`include "ofs_pcie_ss_cfg.vh"

package ofs_plat_host_chan_@group@_fim_gasket_pkg;

    // Largest tag value allowed for AFU->host requests
    localparam MAX_OUTSTANDING_DMA_RD_REQS = ofs_pcie_ss_cfg_pkg::PCIE_EP_MAX_TAGS;
    // Largest tag value permitted in the FIM configuration for host->AFU MMIO reads
    localparam MAX_OUTSTANDING_MMIO_RD_REQS = ofs_pcie_ss_cfg_pkg::PCIE_RP_MAX_TAGS;

`ifdef OFS_PCIE_SS_CFG_FLAG_DM_ENCODING
    localparam ALLOW_DM_ENCODING = ofs_pcie_ss_cfg_pkg::DM_ENCODING_EN;
`else
    // FIMs built before the flag was added support DM encoding
    localparam ALLOW_DM_ENCODING = 1;
`endif

    //
    // Heuristics to pick a working maximum request size for the target
    // platform.
    //
    `undef OFS_PLAT_USE_PU_REQ_SIZE
    `ifdef PLATFORM_FPGA_FAMILY_S10
        // S10 uses an emulated PCIe SS and supports only standard PCIe
        // request sizes.
        `define OFS_PLAT_USE_PU_REQ_SIZE 1
    `endif
    `ifndef OFS_PCIE_SS_CFG_FLAG_TUSER_STORE_COMMIT_REQ
        // Early versions of OFS enforced PU-sized requests in the protocol
        // checker. The change to allowing any DM-encoded size has no flag,
        // so we use a macro that was added at the same time. The store
        // commit flag has nothing to do with the max. request size, but
        // its existence is a clue that the protocol checker will allow
        // large requests.
        `undef OFS_PLAT_USE_PU_REQ_SIZE
        `define OFS_PLAT_USE_PU_REQ_SIZE 1
    `endif

`ifdef OFS_PLAT_USE_PU_REQ_SIZE
    // Maximum read request bits (AFU reading host memory)
    localparam MAX_RD_REQ_SIZE = ofs_pcie_ss_cfg_pkg::MAX_RD_REQ_BYTES * 8;
    // Maximum write payload bits (AFU writing host memory)
    localparam MAX_WR_PAYLOAD_SIZE = ofs_pcie_ss_cfg_pkg::MAX_WR_PAYLOAD_BYTES * 8;
`else
    // Maximum read request bits (AFU reading host memory)
    localparam MAX_RD_REQ_SIZE =
       (ALLOW_DM_ENCODING == 0) ?
           // PU max size
           (ofs_pcie_ss_cfg_pkg::MAX_RD_REQ_BYTES * 8) :
           // With data-mover encoding, the maximum length isn't limited to the
           // host's maximum request size. The PCIe SS will map large requests to
           // legal sizes. 1KB reads get slightly higher bandwidth than 512 bytes.
           // Since the PIM uses data-mover encoding, we can override the FIM's
           // power user maximum of MAX_RD_REQ_BYTES when it is small.
           ((ofs_pcie_ss_cfg_pkg::MAX_RD_REQ_BYTES > 1024) ?
               ofs_pcie_ss_cfg_pkg::MAX_RD_REQ_BYTES * 8 : 1024 * 8);

    // Maximum write payload bits (AFU writing host memory)
    localparam MAX_WR_PAYLOAD_SIZE =
       (ALLOW_DM_ENCODING == 0) ?
           // PU max size
           (ofs_pcie_ss_cfg_pkg::MAX_WR_PAYLOAD_BYTES * 8) :
           // At least 1KB, for the same reason as MAX_RD_REQ_SIZE above.
           ((ofs_pcie_ss_cfg_pkg::MAX_WR_PAYLOAD_BYTES  > 1024) ?
               ofs_pcie_ss_cfg_pkg::MAX_WR_PAYLOAD_BYTES * 8 : 1024 * 8);
`endif

    // Number of interrupt vectors supported
    localparam NUM_AFU_INTERRUPTS = `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_NUM_INTR_VECS;

    localparam NUM_FIM_PCIE_TLP_CH = ofs_pcie_ss_cfg_pkg::NUM_OF_STREAMS;

`ifdef OFS_PCIE_SS_CFG_FLAG_CPL_REORDER
    // Are completions reordered by the PCIe SS?
    import ofs_pcie_ss_cfg_pkg::CPL_REORDER_EN;
    export ofs_pcie_ss_cfg_pkg::CPL_REORDER_EN;
`else
    // Compatibility with older releases - flag not defined
    localparam CPL_REORDER_EN = 0;
`endif

`ifdef OFS_PCIE_SS_CFG_FLAG_CPL_CHAN
    // On which TLP channel are completions returned?
    typedef enum bit[0:0] {
        PCIE_CHAN_A = ofs_pcie_ss_cfg_pkg::PCIE_CHAN_A,
        PCIE_CHAN_B = ofs_pcie_ss_cfg_pkg::PCIE_CHAN_B
    } e_pcie_chan;

    localparam e_pcie_chan CPL_CHAN = e_pcie_chan'(ofs_pcie_ss_cfg_pkg::CPL_CHAN);
`else
    // Compatibility with older releases - flag not defined
    typedef enum bit[0:0] {
        PCIE_CHAN_A,
        PCIE_CHAN_B
    } e_pcie_chan;

    localparam e_pcie_chan CPL_CHAN = PCIE_CHAN_A;
`endif

`ifdef OFS_PCIE_SS_CFG_FLAG_WR_COMMIT_CHAN
    // On which TLP channel are FIM-generated write commits returned?
    localparam e_pcie_chan WR_COMMIT_CHAN = e_pcie_chan'(ofs_pcie_ss_cfg_pkg::WR_COMMIT_CHAN);
`else
    // Compatibility with older releases - flag not defined
    localparam e_pcie_chan WR_COMMIT_CHAN = PCIE_CHAN_B;
`endif

    //
    // Data types in the FIM's AXI streams
    //

    // Data width may be something other than the PCIe SS configuration when
    // links are merged into a single wide stream. Use the PIM's configured value.
    localparam TDATA_WIDTH = `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_DATA_WIDTH;

    // Scale the number of segments by the configured width. For now, we special
    // case when ofs_pcie_ss_cfg_pkg::NUM_OF_SEG is 1 because that likely is set
    // when the code is capable of handling SOP only in data bit 0.
    localparam NUM_OF_SEG = (ofs_pcie_ss_cfg_pkg::NUM_OF_SEG == 1) ? 1 :
                              (ofs_pcie_ss_cfg_pkg::NUM_OF_SEG *
                               (TDATA_WIDTH / ofs_pcie_ss_cfg_pkg::TDATA_WIDTH));

    // The PCIe SS breaks the data vector into segments of equal size.
    // Segments are legal header starting points within the data vector.
    localparam FIM_PCIE_SEG_WIDTH = TDATA_WIDTH / NUM_OF_SEG;
    // Segment width in bytes (useful for indexing tkeep as valid bits)
    localparam FIM_PCIE_SEG_BYTES = FIM_PCIE_SEG_WIDTH / 8;
    typedef logic [FIM_PCIE_SEG_WIDTH-1:0] t_ofs_fim_axis_pcie_seg;

    // Represent the data vector as a union of two options: "payload" is the
    // full width and "segs" breaks payload into NUM_OF_SEG segments.
    typedef union packed {
        logic [TDATA_WIDTH-1:0] payload;
        t_ofs_fim_axis_pcie_seg [NUM_OF_SEG-1:0] segs;
    } t_ofs_fim_axis_pcie_tdata;

    localparam FIM_PCIE_TKEEP_WIDTH = (TDATA_WIDTH / 8);
    typedef logic [FIM_PCIE_TKEEP_WIDTH-1:0] t_ofs_fim_axis_pcie_tkeep;

    // The PIM's representation of PCIe SS user bits adds sop and eop flags
    // to each segment in order to avoid having to recalculate sop at every
    // point that monitors the stream.
    typedef struct packed {
        logic dm_mode;	// Power user (0) or data mover (1) packet encoding
        logic sop;
        logic eop;
    } t_ofs_fim_axis_pcie_seg_tuser;

    typedef t_ofs_fim_axis_pcie_seg_tuser [NUM_OF_SEG-1:0]
        t_ofs_fim_axis_pcie_tuser;


    // Treat a "line" as the width of the PCIe stream's data bus, called a "flit"
    // in the PIM .ini file.
    localparam int MAX_BW_ACTIVE_RD_LINES =
                      `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_MAX_BW_ACTIVE_FLITS_RD;
    localparam int MAX_BW_ACTIVE_WR_LINES =
                      `OFS_PLAT_PARAM_HOST_CHAN_@GROUP@_MAX_BW_ACTIVE_FLITS_WR;


    // Pick out a TLP header from the data vector, given a starting segment index.
    function automatic pcie_ss_hdr_pkg::PCIe_PUReqHdr_t ofs_fim_gasket_pcie_hdr_from_seg(
        input int s,
        input t_ofs_fim_axis_pcie_tdata data
        );

        return data.payload[s*FIM_PCIE_SEG_WIDTH +: $bits(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t)];

    endfunction // ofs_fim_gasket_pcie_hdr_from_seg


    //
    // PF/VF encoding. Import definitions from the FIM if possible.
    //

    // Encoded PF/VF info in the order expected by the PCIe SS for mapping
    // requester and completer IDs.
`ifdef OFS_PCIE_SS_CFG_FLAG_HAS_REQHDR_PF_VF_ID_T
    typedef pcie_ss_hdr_pkg::ReqHdr_pf_vf_id_t t_ofs_fim_pfvf_id;
`else
    typedef struct packed {
        pcie_ss_hdr_pkg::ReqHdr_vf_num_t vf_num;
        logic vf_active;
        pcie_ss_hdr_pkg::ReqHdr_pf_num_t pf_num;
    } t_ofs_fim_pfvf_id;
`endif

    function automatic t_ofs_fim_pfvf_id init_pfvf_id(
        pcie_ss_hdr_pkg::ReqHdr_vf_num_t vf_num,
        logic vf_active,
        pcie_ss_hdr_pkg::ReqHdr_pf_num_t pf_num
        );

`ifdef OFS_PCIE_SS_CFG_FLAG_HAS_REQHDR_PF_VF_ID_T
        return pcie_ss_hdr_pkg::init_ReqHdr_pf_vf_id(vf_num, vf_active, pf_num);
`else
        t_ofs_fim_pfvf_id pfvf;
        pfvf.vf_num = vf_num;
        pfvf.vf_active = vf_active;
        pfvf.pf_num = pf_num;
        return pfvf;
`endif
    endfunction


    //
    // Multiplexed virtual channel management. When the PIM is in
    // OFS_PLAT_HOST_CHAN_MULTIPLEXED mode, PCIe SR-IOV tags are mapped
    // to a virtual channel ID before being passed to an AFU. This way
    // AFUs see a protocol-independent virtual channel.
    //

    localparam NUM_CHAN_PER_MULTIPLEXED_PORT = ofs_plat_host_chan_@group@_pkg::NUM_CHAN_PER_MULTIPLEXED_PORT;
    typedef logic [$clog2(NUM_CHAN_PER_MULTIPLEXED_PORT+1)-1:0] t_multiplexed_port_id;

    // Algorithm for mapping PF/VF in a multiplexed channel to a PIM virtual
    // channel ID.
    typedef enum bit[1:0] {
        // Direct VF number to virtual channel ID. PF is ignored.
        PCIE_VCHAN_MAP_VF_ONLY,
        // Ignore VF, map only PFs
        PCIE_VCHAN_MAP_PF_ONLY,
        // Use both VF and PF when mapping to PIM virtual channels
        PCIE_VCHAN_MAP_FULL
    } e_pcie_vchan_mapping_alg;

    // Choose a PF/VF to virtual channel algorithm.
    function automatic e_pcie_vchan_mapping_alg pick_vchan_mapping_alg(
        input t_multiplexed_port_id num_pfvfs,
        input t_ofs_fim_pfvf_id [NUM_CHAN_PER_MULTIPLEXED_PORT-1:0] multiplexed_pfvfs
        );

        bit vfs_valid = multiplexed_pfvfs[0].vf_active;
        bit vfs_ordered = 1;
        bit pfs_valid = !multiplexed_pfvfs[0].vf_active;
        bit all_pfs_equal = 1;
        pcie_ss_hdr_pkg::ReqHdr_pf_num_t pf_num = multiplexed_pfvfs[0].pf_num;

        for (int c = 1; c < num_pfvfs; c = c + 1) begin
            vfs_valid = vfs_valid || multiplexed_pfvfs[c].vf_active;
            pfs_valid = pfs_valid || !multiplexed_pfvfs[c].vf_active;

            // Test that VFs are dense, starting with 0
            if (multiplexed_pfvfs[c].vf_active && (multiplexed_pfvfs[c].vf_num != c))
                vfs_ordered = 0;

            if (pf_num != multiplexed_pfvfs[c].pf_num)
               all_pfs_equal = 0;
        end

        if (!pfs_valid && vfs_ordered && all_pfs_equal)
            // Virtual channels are equal to VFs
            return PCIE_VCHAN_MAP_VF_ONLY;
        else if (!vfs_valid)
            return PCIE_VCHAN_MAP_PF_ONLY;

        return PCIE_VCHAN_MAP_FULL;
    endfunction // pick_vchan_mapping_alg

    // Map a PF/VF ID to a virtual channel. This algorithm isn't as complicated in
    // HW as it might appear. Nearly all inputs are constant and the usual OFS case
    // is the simple PCIE_VCHAN_MAP_VF_ONLY.
    function automatic t_multiplexed_port_id map_pf_vf_id_to_vchan (
        input t_ofs_fim_pfvf_id pfvf,
        input e_pcie_vchan_mapping_alg mapping_alg,
        input t_multiplexed_port_id num_pfvfs,
        input t_ofs_fim_pfvf_id [NUM_CHAN_PER_MULTIPLEXED_PORT-1:0] multiplexed_pfvfs
        );

        if (mapping_alg == PCIE_VCHAN_MAP_VF_ONLY)
            return pfvf.vf_num;
        else if (mapping_alg == PCIE_VCHAN_MAP_PF_ONLY) begin
            // PFs probably don't start at 0. Generate a table to map PF to VC.
            for (int c = 0; c < num_pfvfs; c = c + 1) begin
                if (pfvf.pf_num == multiplexed_pfvfs[c].pf_num)
                    return c;
            end
        end
        else begin
            // Generate a full table to map PF/VF to VC.
            for (int c = 0; c < num_pfvfs; c = c + 1) begin
                if (pfvf == multiplexed_pfvfs[c])
                    return c;
            end
        end

        return 0;
    endfunction // map_pf_vf_id_to_vchan

    // Same as map_pf_vf_id_vchan but takes separate PF/VF numbers
    function automatic t_multiplexed_port_id map_pf_vf_num_to_vchan (
        input pcie_ss_hdr_pkg::ReqHdr_vf_num_t vf_num,
        input logic vf_active,
        input pcie_ss_hdr_pkg::ReqHdr_pf_num_t pf_num,
        input e_pcie_vchan_mapping_alg mapping_alg,
        input t_multiplexed_port_id num_pfvfs,
        input t_ofs_fim_pfvf_id [NUM_CHAN_PER_MULTIPLEXED_PORT-1:0] multiplexed_pfvfs
        );

        t_ofs_fim_pfvf_id pfvf;
        pfvf.vf_num = vf_num;
        pfvf.vf_active = vf_active;
        pfvf.pf_num = pf_num;

        return map_pf_vf_id_to_vchan(pfvf, mapping_alg, num_pfvfs, multiplexed_pfvfs);
    endfunction // map_pf_vf_num_to_vchan

    // Reverse mapping: virtual channel to PF/VF struct
    function automatic t_ofs_fim_pfvf_id map_vchan_to_pf_vf_id (
        input t_multiplexed_port_id vchan,
        input e_pcie_vchan_mapping_alg mapping_alg,
        input t_multiplexed_port_id num_pfvfs,
        input t_ofs_fim_pfvf_id [NUM_CHAN_PER_MULTIPLEXED_PORT-1:0] multiplexed_pfvfs
        );

        t_ofs_fim_pfvf_id pfvf;

        if (mapping_alg == PCIE_VCHAN_MAP_VF_ONLY) begin
            pfvf.vf_num = vchan;
            pfvf.vf_active = 1'b1;
            pfvf.pf_num = multiplexed_pfvfs[0].pf_num;
        end
        else if (mapping_alg == PCIE_VCHAN_MAP_PF_ONLY) begin
            pfvf.vf_num = 0;
            pfvf.vf_active = 1'b0;
            pfvf.pf_num = multiplexed_pfvfs[vchan].pf_num;
        end
        else begin
            pfvf.vf_num = multiplexed_pfvfs[vchan].vf_num;
            pfvf.vf_active = multiplexed_pfvfs[vchan].vf_active;
            pfvf.pf_num = multiplexed_pfvfs[vchan].pf_num;
        end

        return pfvf;
    endfunction // map_vchan_to_pf_vf_id

    // Reverse mapping: virtual channel to separate PF/VF fields
    function automatic void map_vchan_to_pf_vf_num (
        input t_multiplexed_port_id vchan,
        input e_pcie_vchan_mapping_alg mapping_alg,
        input t_multiplexed_port_id num_pfvfs,
        input t_ofs_fim_pfvf_id [NUM_CHAN_PER_MULTIPLEXED_PORT-1:0] multiplexed_pfvfs,
        output pcie_ss_hdr_pkg::ReqHdr_vf_num_t vf_num,
        output logic vf_active,
        output pcie_ss_hdr_pkg::ReqHdr_pf_num_t pf_num
        );

        t_ofs_fim_pfvf_id pfvf;
        pfvf = map_vchan_to_pf_vf_id(vchan, mapping_alg, num_pfvfs, multiplexed_pfvfs);

        vf_num = pfvf.vf_num;
        vf_active = pfvf.vf_active;
        pf_num = pfvf.pf_num;
    endfunction // map_vchan_to_pf_vf_num


    // synthesis translate_off

    //
    // Debugging functions
    //

    task ofs_fim_gasket_log_pcie_st(
        input int log_fd,
        input string log_class_name,
        input string ctx_name,
        input int unsigned instance_number,
        input t_ofs_fim_axis_pcie_tdata data,
        input t_ofs_fim_axis_pcie_tkeep keep,
        input t_ofs_fim_axis_pcie_tuser user
        );

        automatic int printed_msg = 0;
        for (int s = 0; s < NUM_OF_SEG; s = s + 1)
        begin
            if (keep[s * FIM_PCIE_SEG_BYTES])
            begin
                if (user[s].sop)
                begin
                    // Segment is SOP. Print header.
                    $fwrite(log_fd, "%s: %t %s %0d seg%0d sop %s %s keep 0x%x data 0x%x\n",
                            ctx_name, $time,
                            log_class_name,
                            instance_number, s,
                            (user[s].eop ? "eop" : "   "),
                            pcie_ss_hdr_pkg::func_hdr_to_string(
                                !user[s].dm_mode,
                                ofs_fim_gasket_pcie_hdr_from_seg(s, data)),
                            keep[s * FIM_PCIE_SEG_BYTES +: FIM_PCIE_SEG_BYTES],
                            data);

                    printed_msg = 1;
                end
                else
                begin
                    // Segment is just data
                    $fwrite(log_fd, "%s: %t %s %0d seg%0d     %s keep 0x%x data 0x%x\n",
                            ctx_name, $time,
                            log_class_name,
                            instance_number, s,
                            (user[s].eop ? "eop" : "   "),
                            keep[s * FIM_PCIE_SEG_BYTES +: FIM_PCIE_SEG_BYTES],
                            data);

                    printed_msg = 1;
                end
            end
        end

        // If no message printed yet then the data has no sop or eop. Print the data.
        if (printed_msg == 0)
        begin
            $fwrite(log_fd, "%s: %t %s %0d seg0         data 0x%x\n",
                    ctx_name, $time,
                    log_class_name,
                    instance_number,
                    data);
        end

        $fflush(log_fd);

    endtask // ofs_fim_gasket_log_pcie_st

    // synthesis translate_on

endpackage // ofs_plat_host_chan_@group@_fim_gasket_pkg
