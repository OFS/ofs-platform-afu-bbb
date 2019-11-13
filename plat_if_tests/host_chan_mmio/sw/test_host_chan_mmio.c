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

//
// Test 32, 64 and 512 bit MMIO writes to the FPGA. The FPGA consumes the
// writes in two separate interfaces: one with a 64 bit data bus and the
// other with a 512 bit data bus. The 512 bit bus receives all the writes
// and uses masks to indicate the size and offset of the data. The 64 bit
// bus is similar, except that it does not receive 512 bit writes.
//

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>
#include <inttypes.h>

#include <opae/fpga.h>

// State from the AFU's JSON file, extracted using OPAE's afu_json_mgr script
#include "afu_json_info.h"
#include "test_host_chan_mmio.h"

#define CACHELINE_BYTES 64
#define CL(x) ((x) * CACHELINE_BYTES)
#define MB(x) ((x) * 1048576)

static char *mmio_if_type[] =
{
    "Avalon",
    NULL
};

// ========================================================================
//
//  MMIO access functions. The "word_idx" address space is always relative
//  to the access size. Accessing index 8 in a 32 bit space is equivalent
//  to the low half of index 4 in a 64 bit space.
//
// ========================================================================

static uint64_t
mmio_read64(fpga_handle accel_handle, uint64_t word_idx)
{
    uint64_t v;
    fpga_result r;

    r = fpgaReadMMIO64(accel_handle, 0, sizeof(v) * word_idx, &v);
    assert(FPGA_OK == r);
    return v;
}

static void
mmio_write32(fpga_handle accel_handle, uint64_t word_idx, uint32_t data)
{
    fpga_result r;

    r = fpgaWriteMMIO32(accel_handle, 0, sizeof(data) * word_idx, data);
    assert(FPGA_OK == r);
}

static void
mmio_write64(fpga_handle accel_handle, uint64_t word_idx, uint64_t data)
{
    fpga_result r;

    r = fpgaWriteMMIO64(accel_handle, 0, sizeof(data) * word_idx, data);
    assert(FPGA_OK == r);
}

static void
mmio_write512(fpga_handle accel_handle, uint64_t word_idx, const uint64_t *data)
{
    fpga_result r;

    r = fpgaWriteMMIO512(accel_handle, 0, 8 * sizeof(data) * word_idx, data);
    assert(FPGA_OK == r);
}


int
testHostChanMMIO(
    int argc,
    char *argv[],
    fpga_handle accel_handle,
    t_csr_handle_p csr_handle,
    bool is_ase)
{
    uint64_t idx;
    uint32_t num_tests;

    // Read the AFU status
    uint64_t afu_status = mmio_read64(accel_handle, 0x10);
    if ((afu_status & 0xf) < 1)
        printf("AFU MMIO interface: %s\n", mmio_if_type[afu_status & 0xf]);
    else
        printf("AFU MMIO interface: unknown\n");
    printf("AFU pClk frequency: %ld MHz\n", (afu_status >> 16) & 0xffff);

    // Values to write
    uint64_t data[8];
    data[0] = 0x0706050403020100;
    data[1] = 0x0f0e0d0c0b0a0908;
    data[2] = 0x1716151413121110;
    data[3] = 0x1f1e1d1c1b1a1918;
    data[4] = 0x2726252423222120;
    data[5] = 0x2f2e2d2c2b2a2928;
    data[6] = 0x3736353433323130;
    data[7] = 0x3f3e3d3c3b3a3938;

    printf("\nTesting 32 bit MMIO writes:\n");

    num_tests = 0;
    idx = 0;
    while (idx < 256)
    {
        uint32_t wr_v;
        uint64_t rd_v, rd_idx, rd_mask;
        uint64_t expect_idx, expect_mask;
        uint64_t mmio512_offset64;

        wr_v = data[idx & 7];
        mmio_write32(accel_handle, idx, wr_v);

        // Read back the result recorded by the hardware's 64 bit MMIO space
        // and isolate the half of the 64 bit word that was written
        rd_v = mmio_read64(accel_handle, 0x20);
        rd_v = (idx & 1) ? (rd_v >> 32) : (rd_v & 0xffffffff);

        rd_idx = mmio_read64(accel_handle, 0x30);
        rd_mask = mmio_read64(accel_handle, 0x31);

        if (rd_v != wr_v)
        {
            printf("  idx 0x%lx, value 0x%08x, 64-bit space, incorrect value: 0x%08lx\n",
                   idx, wr_v, rd_v);
            goto error;
        }

        // Is the index correct (in 64 bit space?)
        expect_idx = (idx >> 1);
        if (rd_idx != expect_idx)
        {
            printf("  idx 0x%lx, 64-bit space, incorrect 64 bit index: 0x%lx, expected 0x%lx\n",
                   idx, rd_idx, expect_idx);
            goto error;
        }

        // Is the mask correct?
        expect_mask = (0xf << (4 * (idx & 1)));
        if (rd_mask != expect_mask)
        {
            printf("  idx 0x%lx, 64-bit space, incorrect mask: 0x%lx, expected 0x%lx\n",
                   idx, rd_mask, expect_mask);
            goto error;
        }

        // Read back the result recorded by the hardware's 512 bit MMIO space
        // and isolate the half of the 64 bit word that was written
        mmio512_offset64 = (idx >> 1) & 0x7;
        rd_v = mmio_read64(accel_handle, 0x40 + mmio512_offset64);
        rd_v = (idx & 1) ? (rd_v >> 32) : (rd_v & 0xffffffff);

        rd_idx = mmio_read64(accel_handle, 0x50);
        rd_mask = mmio_read64(accel_handle, 0x51);

        if (rd_v != wr_v)
        {
            printf("  idx 0x%lx, value 0x%08x, 512-bit space, incorrect value: 0x%08lx\n",
                   idx, wr_v, rd_v);
            goto error;
        }

        // Is the index correct (in 512 bit space?)
        expect_idx = (idx >> 4);
        if (rd_idx != expect_idx)
        {
            printf("  idx 0x%lx, 512-bit space, incorrect 64 bit index: 0x%lx, expected 0x%lx\n",
                   idx, rd_idx, expect_idx);
            goto error;
        }

        // Is the mask correct?
        expect_mask = ((uint64_t)0xf << ((8 * mmio512_offset64) + (4 * (idx & 1))));
        if (rd_mask != expect_mask)
        {
            printf("  idx 0x%lx, 512-bit space, incorrect mask: 0x%lx, expected 0x%lx\n",
                   idx, rd_mask, expect_mask);
            goto error;
        }

        num_tests += 1;
        idx += 53;
    }

    printf("    PASS - %d tests\n", num_tests);

    printf("\nTesting 64 bit MMIO writes:\n");

    num_tests = 0;
    idx = 0;
    while (idx < 256)
    {
        uint64_t wr_v;
        uint64_t rd_v, rd_idx, rd_mask;
        uint64_t expect_idx, expect_mask;
        uint64_t mmio512_offset64;

        wr_v = data[idx & 7];
        mmio_write64(accel_handle, idx, wr_v);

        // Read back the result recorded by the hardware's 64 bit MMIO space
        rd_v = mmio_read64(accel_handle, 0x20);
        rd_idx = mmio_read64(accel_handle, 0x30);
        rd_mask = mmio_read64(accel_handle, 0x31);

        if (rd_v != wr_v)
        {
            printf("  idx 0x%lx, value 0x%08lx, 64-bit space, incorrect value: 0x%08lx\n",
                   idx, wr_v, rd_v);
            goto error;
        }

        // Is the index correct (in 64 bit space?)
        expect_idx = idx;
        if (rd_idx != expect_idx)
        {
            printf("  idx 0x%lx, 64-bit space, incorrect 64 bit index: 0x%lx, expected 0x%lx\n",
                   idx, rd_idx, expect_idx);
            goto error;
        }

        // Is the mask correct?
        expect_mask = 0xff;
        if (rd_mask != expect_mask)
        {
            printf("  idx 0x%lx, 64-bit space, incorrect mask: 0x%lx, expected 0x%lx\n",
                   idx, rd_mask, expect_mask);
            goto error;
        }

        // Read back the result recorded by the hardware's 512 bit MMIO space
        mmio512_offset64 = idx & 0x7;
        rd_v = mmio_read64(accel_handle, 0x40 + mmio512_offset64);
        rd_idx = mmio_read64(accel_handle, 0x50);
        rd_mask = mmio_read64(accel_handle, 0x51);

        if (rd_v != wr_v)
        {
            printf("  idx 0x%lx, value 0x%08lx, 512-bit space, incorrect value: 0x%08lx\n",
                   idx, wr_v, rd_v);
            goto error;
        }

        // Is the index correct (in 512 bit space?)
        expect_idx = (idx >> 3);
        if (rd_idx != expect_idx)
        {
            printf("  idx 0x%lx, 512-bit space, incorrect 64 bit index: 0x%lx, expected 0x%lx\n",
                   idx, rd_idx, expect_idx);
            goto error;
        }

        // Is the mask correct?
        expect_mask = ((uint64_t)0xff << (8 * mmio512_offset64));
        if (rd_mask != expect_mask)
        {
            printf("  idx 0x%lx, 512-bit space, incorrect mask: 0x%lx, expected 0x%lx\n",
                   idx, rd_mask, expect_mask);
            goto error;
        }

        num_tests += 1;
        idx += 53;
    }

    printf("    PASS - %d tests\n", num_tests);

    printf("\nTesting 512 bit MMIO writes:\n");

    uint64_t prev_rd_v = mmio_read64(accel_handle, 0x20);
    uint64_t prev_rd_idx = mmio_read64(accel_handle, 0x30);
    uint64_t prev_rd_mask = mmio_read64(accel_handle, 0x31);

    idx = 57;
    mmio_write512(accel_handle, idx, data);

    // Read back the result recorded by the hardware's 64 bit MMIO space.
    // It should not change.
    if ((prev_rd_v != mmio_read64(accel_handle, 0x20)) ||
        (prev_rd_idx != mmio_read64(accel_handle, 0x30)) ||
        (prev_rd_mask != mmio_read64(accel_handle, 0x31)))
    {
        printf("  512 bit MMIO write should not reach the 64 bit MMIO FPGA interface!\n");
        goto error;
    }

    // Read back the result recorded by the hardware's 512 bit MMIO space
    for (int i = 0; i < 8; i += 1)
    {
        uint64_t rd_v = mmio_read64(accel_handle, 0x40 + i);
        if (data[i] != rd_v)
        {
            printf("  idx 0x%lx [%d], value 0x%08lx, 512-bit space, incorrect value: 0x%08lx\n",
                   idx, i, data[i], rd_v);
            goto error;
        }
    }

    uint64_t m512_idx = mmio_read64(accel_handle, 0x50);
    uint64_t m512_mask = mmio_read64(accel_handle, 0x51);

    // Is the index correct (in 512 bit space?)
    if (m512_idx != idx)
    {
        printf("  idx 0x%lx, 512-bit space, incorrect index: 0x%lx\n",
               idx, m512_idx);
        goto error;
    }

    // Is the mask correct?
    if (m512_mask != ~(uint64_t)0)
    {
        printf("  idx 0x%lx, 512-bit space, incorrect mask: 0x%lx\n",
               idx, m512_mask);
        goto error;
    }

    printf("    PASS\n");

    return 0;

  error:
    return 1;
}
