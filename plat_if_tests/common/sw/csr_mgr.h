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

#ifndef __CSR_MGR_H__
#define __CSR_MGR_H__

#include <stdint.h>
#include <opae/fpga.h>

#ifdef __cplusplus
extern "C"
{
#endif

typedef enum
{
    CSR_AFU_DFH = 0,
    CSR_AFU_ID_L = 1,
    CSR_AFU_ID_H = 2,

    CSR_RD_CTRL_CONFIG_INFO = 0x10,
    CSR_RD_CTRL_ENG_RUN_MASK = 0x11,
    CSR_RD_CTRL_ENG_ACTIVE_MASK = 0x12,
    CSR_RD_CTRL_ENG_CYCLES = 0x13,
    CSR_RD_CTRL_ENG_PCLK_CYCLES = 0x14,
    CSR_WR_CTRL_ENG_ENABLE_MASK = 0x10,
    CSR_WR_CTRL_ENG_DISABLE_MASK = 0x11,

    CSR_ENG_GLOB_BASE = 0x020,
    CSR_ENG_BASE = 0x400
}
t_csr_enum;

typedef struct
{
    fpga_handle fpga_handle;
    uint32_t mmio_num;
}
t_csr_handle;

typedef const t_csr_handle* t_csr_handle_p;

// All the CSR calls expect a CSR handle
t_csr_handle_p csrAllocHandle(fpga_handle fpga_handle, uint32_t mmio_num);
fpga_result csrReleaseHandle(t_csr_handle_p csr_handle);

//
// Various configuration details
//
uint32_t csrGetNumEngines(t_csr_handle_p csr_handle);
// This function computes the engine's clock frequency relative to the
// known pClk reference. It can only be called after at least one engine
// is enabled and then disabled. (This is because it depends on the engine
// cycle counters, which run only when an engine is enabled. The engines
// must then be disabled so that multiple clock counters can be read while
// the counters are stopped.)
float csrGetClockMHz(t_csr_handle_p csr_handle);
// Cycles spent running (enabled then disabled) in the engine clock domain.
uint64_t csrGetClockCycles(t_csr_handle_p csr_handle);

// Enable or disable engines. Each bit in the mask corresponds to an engine.
fpga_result csrEnableEngines(t_csr_handle_p csr_handle, uint64_t engine_mask);
fpga_result csrDisableEngines(t_csr_handle_p csr_handle, uint64_t engine_mask);

// Engine state. These return a bit mask, each bit corresponding to an engine.
// Engines enabled are those selected by the enable method above. Those that
// are active may be disabled but still have outstanding requests in flight.
uint64_t csrGetEnginesEnabled(t_csr_handle_p csr_handle);
uint64_t csrGetEnginesActive(t_csr_handle_p csr_handle);

//
// Read write the 16 global engine CSRs
//
uint64_t csrEngGlobRead(t_csr_handle_p csr_handle, uint32_t idx);
fpga_result csrEngGlobWrite(t_csr_handle_p csr_handle, uint32_t idx, uint64_t value);

//
// Read write the 16 private engine CSRs
//
uint64_t csrEngRead(t_csr_handle_p csr_handle, uint32_t eng_num, uint32_t idx);
fpga_result csrEngWrite(t_csr_handle_p csr_handle, uint32_t eng_num, uint32_t idx,
                        uint64_t value);

//
// Generic CSR read/write (index is in 64 bit data space, so index 1 is byte
// address 8).
//
uint64_t csrRead(t_csr_handle_p csr_handle, uint64_t idx);
fpga_result csrWrite(t_csr_handle_p csr_handle, uint64_t idx, uint64_t value);

#ifdef __cplusplus
}
#endif
#endif // __CSR_MGR_H__
