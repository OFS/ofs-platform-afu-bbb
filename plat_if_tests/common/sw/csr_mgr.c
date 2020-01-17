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
    if ((eng_num > 16) || (idx > 16)) return -1;
    return csrRead(csr_handle,
                   CSR_ENG_BASE | (eng_num << 4) | idx);
}

fpga_result
csrEngWrite(t_csr_handle_p csr_handle, uint32_t eng_num, uint32_t idx,
            uint64_t value)
{
    if ((eng_num > 16) || (idx > 16)) return -1;
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
