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
       // With data-mover encoding, the maximum length isn't limited to the
       // host's maximum request size. The PCIe SS will map large requests to
       // legal sizes. 1KB reads get slightly higher bandwidth than 512 bytes.
       // Since the PIM uses data-mover encoding, we can override the FIM's
       // power user maximum of MAX_RD_REQ_BYTES when it is small.
       (ofs_pcie_ss_cfg_pkg::MAX_RD_REQ_BYTES > 1024) ?
           ofs_pcie_ss_cfg_pkg::MAX_RD_REQ_BYTES * 8 : 1024 * 8;
    // Maximum write payload bits (AFU writing host memory)
    localparam MAX_WR_PAYLOAD_SIZE =
       // At least 1KB, for the same reason as MAX_RD_REQ_SIZE above.
       (ofs_pcie_ss_cfg_pkg::MAX_WR_PAYLOAD_BYTES  > 1024) ?
           ofs_pcie_ss_cfg_pkg::MAX_WR_PAYLOAD_BYTES * 8 : 1024 * 8;
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
