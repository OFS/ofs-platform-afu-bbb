// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#include <stdlib.h>

#include "csr_mgr.h"

t_csr_handle_p
csrAllocHandle(fpga_handle fpga_handle, uint32_t mmio_num)
{
    t_csr_handle* h = malloc(sizeof(t_csr_handle));
    if (h == NULL) return NULL;

    h->fpga_handle = fpga_handle;
    h->mmio_num = mmio_num;
    return h;
}

fpga_result
csrReleaseHandle(t_csr_handle_p csr_handle)
{
    free((void*)csr_handle);
    return FPGA_OK;
}

uint32_t
csrGetNumEngines(t_csr_handle_p csr_handle)
{
    if (! csr_handle) return -1;
    uint64_t v = csrRead(csr_handle, CSR_RD_CTRL_CONFIG_INFO);
    return v & 0xff;
}

float
csrGetClockMHz(t_csr_handle_p csr_handle)
{
    if (! csr_handle) return 0;

    // This only works if all engines are disabled so the counters are stopped
    if (csrGetEnginesEnabled(csr_handle) != 0) return 0;
    
    uint64_t pclk_mhz;
    pclk_mhz = (csrRead(csr_handle, CSR_RD_CTRL_CONFIG_INFO) >> 8) & 0xffff;

    uint64_t clk_cycles, pclk_cycles;
    clk_cycles = csrGetClockCycles(csr_handle);
    pclk_cycles = csrRead(csr_handle, CSR_RD_CTRL_ENG_PCLK_CYCLES);
    if (!clk_cycles || !pclk_cycles) return 0;

    double freq;
    freq = (double) pclk_mhz * ((double) clk_cycles / (double) pclk_cycles);
    
    return (float) freq;
}

uint64_t
csrGetClockCycles(t_csr_handle_p csr_handle)
{
    return csrRead(csr_handle, CSR_RD_CTRL_ENG_CYCLES);
}

fpga_result
csrEnableEngines(t_csr_handle_p csr_handle, uint64_t engine_mask)
{
    return csrWrite(csr_handle, CSR_WR_CTRL_ENG_ENABLE_MASK, engine_mask);
}

fpga_result
csrDisableEngines(t_csr_handle_p csr_handle, uint64_t engine_mask)
{
    return csrWrite(csr_handle, CSR_WR_CTRL_ENG_DISABLE_MASK, engine_mask);
}

uint64_t
csrGetEnginesEnabled(t_csr_handle_p csr_handle)
{
    return csrRead(csr_handle, CSR_RD_CTRL_ENG_RUN_MASK);
}

uint64_t
csrGetEnginesActive(t_csr_handle_p csr_handle)
{
    return csrRead(csr_handle, CSR_RD_CTRL_ENG_ACTIVE_MASK);
}

uint64_t
csrEngGlobRead(t_csr_handle_p csr_handle, uint32_t idx)
{
    if (idx > 16) return -1;
    return csrRead(csr_handle, CSR_ENG_GLOB_BASE + idx);
}

fpga_result
csrEngGlobWrite(t_csr_handle_p csr_handle, uint32_t idx, uint64_t value)
{
    return csrWrite(csr_handle, CSR_ENG_GLOB_BASE + idx, value);
}

//
// Read write the 16 private engine CSRs
//
uint64_t
csrEngRead(t_csr_handle_p csr_handle, uint32_t eng_num, uint32_t idx)
{
    if ((eng_num > 64) || (idx > 16)) return -1;
    return csrRead(csr_handle,
                   CSR_ENG_BASE | (eng_num << 4) | idx);
}

fpga_result
csrEngWrite(t_csr_handle_p csr_handle, uint32_t eng_num, uint32_t idx,
            uint64_t value)
{
    if ((eng_num > 64) || (idx > 16)) return -1;
    return csrWrite(csr_handle,
                    CSR_ENG_BASE | (eng_num << 4) | idx,
                    value);
}

uint64_t
csrRead(t_csr_handle_p csr_handle, uint64_t idx)
{
    fpga_result r;
    uint64_t v;
    if (! csr_handle) return -1;

    r = fpgaReadMMIO64(csr_handle->fpga_handle, csr_handle->mmio_num,
                       idx * 8, &v);
    if (r != FPGA_OK) return -1;

    return v;
}

fpga_result
csrWrite(t_csr_handle_p csr_handle, uint64_t idx, uint64_t value)
{
    if (! csr_handle) return FPGA_INVALID_PARAM;
    return fpgaWriteMMIO64(csr_handle->fpga_handle, csr_handle->mmio_num,
                           idx * 8, value);
}
