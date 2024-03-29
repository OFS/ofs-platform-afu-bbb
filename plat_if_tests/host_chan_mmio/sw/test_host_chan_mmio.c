// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

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
    "AXI Lite",
    NULL
};

static bool mmio512_wr_supported;


// ========================================================================
//
//  MMIO access functions. The "word_idx" address space is always relative
//  to the access size. Accessing index 8 in a 32 bit space is equivalent
//  to the low half of index 4 in a 64 bit space.
//
// ========================================================================

static uint32_t
mmio_read32(fpga_handle accel_handle, uint64_t word_idx)
{
    uint32_t v;
    fpga_result r;

    r = fpgaReadMMIO32(accel_handle, 0, sizeof(v) * word_idx, &v);
    assert(FPGA_OK == r);
    return v;
}

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

    if (mmio512_wr_supported)
    {
        r = fpgaWriteMMIO512(accel_handle, 0, 8 * sizeof(data) * word_idx, data);
        assert(FPGA_OK == r);
    }
    else
    {
        // Emulate 512 bit writes with multiple 64 bit writes.
        for (int i = 7; i >= 0; i -= 1)
        {
            mmio_write64(accel_handle, 8 * word_idx + i, data[i]);
        }
    }
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
    uint32_t rd_bus_width = ((afu_status >> 14) & 3) ? 512 : 64;
    mmio512_wr_supported = (afu_status >> 4) & 1;
    if ((afu_status & 0xf) < 2)
        printf("AFU MMIO interface: %s\n", mmio_if_type[afu_status & 0xf]);
    else
        printf("AFU MMIO interface: unknown\n");
    printf("AFU MMIO read bus width: %d bits\n", rd_bus_width);
    printf("512 bit MMIO write supported: %s\n", (mmio512_wr_supported ? "yes" : "no"));
    printf("AFU pClk frequency: %ld MHz\n", (afu_status >> 16) & 0xffff);

    // Simple test of 32 bit reads, making sure the proper half of 64 bit
    // registers is returned.
    printf("\nTesting 32 bit MMIO reads:\n");
    uint64_t afu_idl = mmio_read64(accel_handle, 1);
    uint32_t afu_idl_l32 = mmio_read32(accel_handle, 2);
    uint32_t afu_idl_h32 = mmio_read32(accel_handle, 3);
    if ((uint32_t)afu_idl != afu_idl_l32)
    {
        printf("  FAIL idx 2: expected 0x%08x, found 0x%08x\n",
               (uint32_t)afu_idl, afu_idl_l32);
        goto error;
    }
    if ((afu_idl >> 32) != afu_idl_h32)
    {
        printf("  FAIL idx 3, expected 0x%08lx, found 0x%08x\n",
               afu_idl >> 32, afu_idl_h32);
        goto error;
    }

    // Test that 32 bit addresses are interpreted correctly. CSR 7
    // returns the requested address as a byte offset in both 32
    // bit halves of the register.
    idx = mmio_read64(accel_handle, 7);
    if (idx != 0x3800000038)
    {
        printf("  FAIL idx 7: expected 0x3800000038, found 0x%lx\n", idx);
        goto error;
    }

    // Low half of 64 bit register 7 as a 32 bit request
    uint32_t idx32 = mmio_read32(accel_handle, 14);
    if (idx32 != (7 << 3))
    {
        printf("  FAIL idx 7: expected 0x%x, found 0x%x\n", (7 << 3), idx32);
        goto error;
    }

    printf("  PASS - 4 tests\n");

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
            printf("  FAIL - idx 0x%lx, value 0x%08x, 64-bit space, incorrect value: 0x%08lx\n",
                   idx, wr_v, rd_v);
            goto error;
        }

        // Is the index correct (in 64 bit space?). All the AFUs convert the index
        // to a byte index in the response. On AXI that is the true encoding.
        // The Avalon-based AFU adds low bits to the index to convert to byte-based.
        expect_idx = (idx << 2);
        if (rd_idx != expect_idx)
        {
            printf("  FAIL - idx 0x%lx, 64-bit space, incorrect 64 bit index: 0x%lx, expected 0x%lx\n",
                   idx, rd_idx, expect_idx);
            goto error;
        }

        // Is the mask correct?
        expect_mask = (0xf << (4 * (idx & 1)));
        if (rd_mask != expect_mask)
        {
            printf("  FAIL - idx 0x%lx, 64-bit space, incorrect mask: 0x%lx, expected 0x%lx\n",
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
            printf("  FAIL - idx 0x%lx, value 0x%08x, 512-bit space, incorrect value: 0x%08lx\n",
                   idx, wr_v, rd_v);
            goto error;
        }

        // Is the index correct (in 512 bit space?) (byte addressable)
        expect_idx = (idx << 2);
        if (rd_idx != expect_idx)
        {
            printf("  FAIL - idx 0x%lx, 512-bit space, incorrect 64 bit index: 0x%lx, expected 0x%lx\n",
                   idx, rd_idx, expect_idx);
            goto error;
        }

        // Is the mask correct?
        expect_mask = ((uint64_t)0xf << ((8 * mmio512_offset64) + (4 * (idx & 1))));
        if (rd_mask != expect_mask)
        {
            printf("  FAIL - idx 0x%lx, 512-bit space, incorrect mask: 0x%lx, expected 0x%lx\n",
                   idx, rd_mask, expect_mask);
            goto error;
        }

        num_tests += 1;
        idx += 53;
    }

    printf("  PASS - %d tests\n", num_tests);

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
            printf("  FAIL - idx 0x%lx, value 0x%08lx, 64-bit space, incorrect value: 0x%08lx\n",
                   idx, wr_v, rd_v);
            goto error;
        }

        // Is the index correct (in 64 bit space?). All the AFUs convert the index
        // to a byte index in the response. On AXI that is the true encoding.
        // The Avalon-based AFU adds low bits to the index to convert to byte-based.
        expect_idx = (idx << 3);
        if (rd_idx != expect_idx)
        {
            printf("  FAIL - idx 0x%lx, 64-bit space, incorrect 64 bit index: 0x%lx, expected 0x%lx\n",
                   idx, rd_idx, expect_idx);
            goto error;
        }

        // Is the mask correct?
        expect_mask = 0xff;
        if (rd_mask != expect_mask)
        {
            printf("  FAIL - idx 0x%lx, 64-bit space, incorrect mask: 0x%lx, expected 0x%lx\n",
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
            printf("  FAIL - idx 0x%lx, value 0x%08lx, 512-bit space, incorrect value: 0x%08lx\n",
                   idx, wr_v, rd_v);
            goto error;
        }

        // Is the index correct (in 512 bit space?). All AFUs respond here in
        // byte-addressable space.
        expect_idx = (idx << 3);
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
            printf("  FAIL - idx 0x%lx, 512-bit space, incorrect mask: 0x%lx, expected 0x%lx\n",
                   idx, rd_mask, expect_mask);
            goto error;
        }

        num_tests += 1;
        idx += 53;
    }

    printf("  PASS - %d tests\n", num_tests);

    printf("\nTesting 512 bit MMIO writes:\n");

    uint64_t prev_rd_v = mmio_read64(accel_handle, 0x20);
    uint64_t prev_rd_idx = mmio_read64(accel_handle, 0x30);
    uint64_t prev_rd_mask = mmio_read64(accel_handle, 0x31);

    idx = 57;
    mmio_write512(accel_handle, idx, data);

    // Read back the result recorded by the hardware's 64 bit MMIO space.
    // It should not change, unless 512 bit writes are emulated using 64 bit writes.
    if (mmio512_wr_supported && (rd_bus_width <= 64) &&
        ((prev_rd_v != mmio_read64(accel_handle, 0x20)) ||
         (prev_rd_idx != mmio_read64(accel_handle, 0x30)) ||
         (prev_rd_mask != mmio_read64(accel_handle, 0x31))))
    {
        printf("  FAIL - 512 bit MMIO write should not reach the 64 bit MMIO FPGA interface!\n");
        goto error;
    }

    // Read back the result recorded by the hardware's 512 bit MMIO space
    for (int i = 0; i < 8; i += 1)
    {
        uint64_t rd_v = mmio_read64(accel_handle, 0x40 + i);
        if (data[i] != rd_v)
        {
            printf("  FAIL - idx 0x%lx [%d], value 0x%08lx, 512-bit space, incorrect value: 0x%08lx\n",
                   idx, i, data[i], rd_v);
            goto error;
        }
    }

    uint64_t m512_idx = mmio_read64(accel_handle, 0x50);
    uint64_t m512_mask = mmio_read64(accel_handle, 0x51);

    // Is the index correct (in 512 bit space?)
    if (m512_idx != (idx << 6))
    {
        printf("  FAIL - idx 0x%lx, 512-bit space, incorrect index: 0x%lx, expected 0x%lx\n",
               idx, m512_idx, (idx << 6));
        goto error;
    }

    // Is the mask correct? Skip if 512 bit writes are unavailable
    if (mmio512_wr_supported && (m512_mask != ~(uint64_t)0))
    {
        printf("  FAIL - idx 0x%lx, 512-bit space, incorrect mask: 0x%lx\n",
               idx, m512_mask);
        goto error;
    }

    printf("  PASS\n");

    return 0;

  error:
    return 1;
}
