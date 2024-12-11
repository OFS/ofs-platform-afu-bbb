// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Test one or more host memory interfaces, varying address alignment and
// burst sizes.
//

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <assert.h>
#include <inttypes.h>
#include <uuid/uuid.h>
#include <time.h>
#include <immintrin.h>
#include <cpuid.h>
#include <numa.h>

#include <opae/fpga.h>

#ifdef FPGA_NEAR_MEM_MAP
#include <opae/fpga_near_mem_map.h>
#endif

// State from the AFU's JSON file, extracted using OPAE's afu_json_mgr script
#include "afu_json_info.h"
#include "test_host_chan_params.h"

#define CACHELINE_BYTES 64
#define CL(x) ((x) * CACHELINE_BYTES)
#define MB(x) ((x) * 1048576)

#define PROTECTION (PROT_READ | PROT_WRITE)

#ifndef MAP_HUGETLB
#define MAP_HUGETLB 0x40000
#endif
#ifndef MAP_HUGE_SHIFT
#define MAP_HUGE_SHIFT 26
#endif

#define MAP_1G_HUGEPAGE (0x1e << MAP_HUGE_SHIFT) /* 2 ^ 0x1e = 1G */

#define FLAGS_4K (MAP_PRIVATE | MAP_ANONYMOUS)
#define FLAGS_2M (FLAGS_4K | MAP_HUGETLB)
#define FLAGS_1G (FLAGS_2M | MAP_1G_HUGEPAGE)


// Engine's address mode
typedef enum
{
    ADDR_MODE_IOADDR = 0,
    ADDR_MODE_HOST_PHYSICAL = 1,
    ADDR_MODE_VIRTUAL = 3
}
t_fpga_addr_mode;

const char* addr_mode_str[] =
{
    "IOADDR",
    "Host physical",
    "reserved",
    "Virtual"
};


//
// Hold shared memory buffer details for one engine
//
typedef struct
{
    fpga_handle accel_handle;
    t_csr_handle_p csr_handle;
    uint32_t accel_eng_idx;

    volatile uint64_t *rd_buf;
    uint64_t rd_buf_ioaddr;
    uint64_t rd_buf_ioaddr_enc;     // IOADDR divided by data bus width
    uint64_t rd_wsid;

    volatile uint64_t *wr_buf;
    uint64_t wr_buf_ioaddr;
    uint64_t wr_buf_ioaddr_enc;     // IOADDR divided by data bus width
    uint64_t wr_wsid;

    struct bitmask* numa_rd_mem_mask;
    struct bitmask* numa_wr_mem_mask;
    uint32_t data_bus_bytes;
    uint32_t max_burst_size;
    uint32_t group;
    uint32_t eng_type;
    t_fpga_addr_mode addr_mode;
    bool natural_bursts;
    bool ordered_read_responses;
    bool masked_writes;

    double fim_ifc_mhz;
}
t_engine_buf;

static bool s_is_ase;
static t_engine_buf* s_eng_bufs;
static uint32_t s_num_engines;
static double s_afu_mhz;

static char *engine_type[] = 
{
    "CCI-P",
    "Avalon-MM",
    "AXI-MM",
    NULL
};


//
// Taken from https://github.com/pmem/pmdk/blob/master/src/libpmem2/x86_64/flush.h.
// The clflushopt instruction was added for Skylake and isn't in <immintrin.h>
// _mm_clflushopt() in many of the compilers currently in use.
//
static inline void
asm_clflushopt(const void *addr)
{
    asm volatile(".byte 0x66; clflush %0" : "+m" \
        (*(volatile char *)(addr)));
}

//
// Flush a range of lines from the cache hierarchy in the entire coherence
// domain. (All cores all sockets)
//
static void
flushRange(void* start, size_t len)
{
    uint8_t* cl = start;
    uint8_t* end = start + len;

    // Does the CPU support clflushopt?
    static bool checked_clflushopt = false;
    static bool supports_clflushopt = false;

    if (! checked_clflushopt)
    {
        checked_clflushopt = true;
        supports_clflushopt = false;

        unsigned int eax, ebx, ecx, edx;
        if (__get_cpuid_max(0, 0) >= 7)
        {
            __cpuid_count(7, 0, eax, ebx, ecx, edx);
            // bit_CLFLUSHOPT is (1 << 23)
            supports_clflushopt = (((1 << 23) & ebx) != 0);
            printf("#  Processor supports clflushopt: %d\n", supports_clflushopt);
        }
    }
    if (! supports_clflushopt) return;

    while (cl < end)
    {
        asm_clflushopt(cl);
        cl += CACHELINE_BYTES;
    }

    _mm_sfence();
}


//
// Prefetch a range into the local cache.
//
static void
prefetchRange(void* start, size_t len)
{
    uint8_t* cl = start;
    uint8_t* end = start + len;
    static volatile uint64_t sum = 0;

    while (cl < end)
    {
        sum += *cl;
        cl += CACHELINE_BYTES;
    }
}


//
// Allocate a buffer in I/O memory, shared with the FPGA.
//
static void*
allocSharedBuffer(
    fpga_handle accel_handle,
    size_t size,
    t_fpga_addr_mode addr_mode,
    struct bitmask *numa_mem_mask,
    uint64_t *wsid,
    uint64_t *ioaddr)
{
    fpga_result r;
    void* buf;

    int flags;
    if (size >= MB(1024))
        flags = FLAGS_1G;
    else if (size >= 2 * MB(1))
        flags = FLAGS_2M;
    else
        flags = FLAGS_4K;

    // Preserve current NUMA configuration
    struct bitmask *numa_mems_preserve;
    numa_mems_preserve = numa_get_membind();

    // Limit NUMA to what the port requests (except in simulation)
    if (!s_is_ase) numa_set_membind(numa_mem_mask);

    // Allocate a buffer
    buf = mmap(NULL, size, (PROT_READ | PROT_WRITE), flags, -1, 0);
    assert(NULL != buf);

    // Pin the buffer
    r = fpgaPrepareBuffer(accel_handle, size, (void*)&buf, wsid, FPGA_BUF_PREALLOCATED);
    if (FPGA_OK != r) return NULL;

    // Restore NUMA configuration
    numa_set_membind(numa_mems_preserve);
    numa_bitmask_free(numa_mems_preserve);

    // Get the physical address of the buffer in the accelerator
    r = fpgaGetIOAddress(accel_handle, *wsid, ioaddr);
    assert(FPGA_OK == r);

    // Physical addresses? (ASE doesn't support this)
    if ((addr_mode == ADDR_MODE_HOST_PHYSICAL) && !s_is_ase)
    {
#ifdef FPGA_NEAR_MEM_MAP
        // Call libfpga_near_mem_map from BBB repository for address info.
        // FPGA_NEAR_MEM_MAP has been tested already in initEngine().
        fpga_near_mem_map_buf_info buf_info;
        r = fpgaNearMemGetPageAddrInfo((void*)buf, &buf_info);
        if (FPGA_OK != r)
        {
            fprintf(stderr,
                    "Physical translation from VA %p failed. Is the fpga_near_mem_map driver from\n"
                    "the OPAE intel-fpga-bbb repository installed properly?\n", buf);
            exit(1);
        }

        *ioaddr = buf_info.phys_addr - buf_info.phys_space_base;
#endif
    }

    // The test engines treat a zero buffer IOVA as a hint to disable the engine.
    // If IOVA is zero, just leave it allocated as a placeholder and get another
    // buffer.
    if (0 == *ioaddr)
    {
        buf = allocSharedBuffer(accel_handle, size, addr_mode, numa_mem_mask,
                                wsid, ioaddr);
    }

    return buf;
}


static void
initReadBuf(
    volatile uint64_t *buf,
    size_t n_bytes)
{
    uint64_t cnt = 1;

    // The data in the read buffers doesn't really matter as long as there are
    // unique values in each line. Reads will be checked with a hash (CRC).
    while (n_bytes -= sizeof(uint64_t))
    {
        *buf++ = cnt++;
    }
}


static void
engineErrorAndExit(
    uint32_t num_engines,
    uint64_t emask
)
{
    printf("\nEngine mask 0x%lx failure:\n", emask);
    for (uint32_t glob_e = 0; glob_e < num_engines; glob_e += 1)
    {
        t_csr_handle_p csr_handle = s_eng_bufs[glob_e].csr_handle;

        if (emask & ((uint64_t)1 << glob_e))
        {
            printf("  Engine %d state:\n", glob_e);

            uint32_t e = s_eng_bufs[glob_e].accel_eng_idx;
            printf("    Read burst requests: %ld\n", csrEngRead(csr_handle, e, 1));
            if (s_eng_bufs[e].eng_type == 2)
            {
                printf("    Read burst responses: %ld\n", csrEngRead(csr_handle, e, 6));
            }
            printf("    Read lines responses: %ld\n", csrEngRead(csr_handle, e, 2));

            printf("    Write burst requests: %ld\n", csrEngRead(csr_handle, e, 3));
            printf("    Write burst responses: %ld\n", csrEngRead(csr_handle, e, 4));
        }
    }

    exit(1);
}


static void
initEngine(
    uint32_t e,
    fpga_handle accel_handle,
    t_csr_handle_p csr_handle,
    uint32_t accel_eng_idx)
{
    s_eng_bufs[e].accel_handle = accel_handle;
    s_eng_bufs[e].csr_handle = csr_handle;
    s_eng_bufs[e].accel_eng_idx = accel_eng_idx;

    // Get the maximum burst size for the engine.
    uint64_t r = csrEngRead(csr_handle, accel_eng_idx, 0);
    s_eng_bufs[e].max_burst_size = r & 0x7fff;
    s_eng_bufs[e].natural_bursts = (r >> 15) & 1;
    s_eng_bufs[e].ordered_read_responses = (r >> 39) & 1;
    s_eng_bufs[e].masked_writes = (r >> 50) & 1;
    s_eng_bufs[e].addr_mode = (r >> 40) & 3;
    s_eng_bufs[e].group = (r >> 47) & 7;
    s_eng_bufs[e].eng_type = (r >> 35) & 7;
    s_eng_bufs[e].data_bus_bytes = ((r >> 51) & 3) * 64;
    if (s_eng_bufs[e].data_bus_bytes == 0)
        s_eng_bufs[e].data_bus_bytes = 32;

    uint32_t eng_num = (r >> 42) & 31;
    printf("#  Engine %d type: %s\n", e, engine_type[s_eng_bufs[e].eng_type]);
    printf("#  Engine %d data bus bytes: %d\n", e, s_eng_bufs[e].data_bus_bytes);
    printf("#  Engine %d max burst size: %d\n", e, s_eng_bufs[e].max_burst_size);
    printf("#  Engine %d natural bursts: %d\n", e, s_eng_bufs[e].natural_bursts);
    printf("#  Engine %d ordered read responses: %d\n", e, s_eng_bufs[e].ordered_read_responses);
    printf("#  Engine %d masked writes allowed: %d\n", e, s_eng_bufs[e].masked_writes);
    printf("#  Engine %d addressing mode: %s\n", e, addr_mode_str[s_eng_bufs[e].addr_mode]);
    printf("#  Engine %d group: %d\n", e, s_eng_bufs[e].group);

    // 64 bit mask of valid NUMA nodes, according to the FPGA configuration
    struct bitmask* numa_rd_mask;
    struct bitmask* numa_wr_mask;
    if ((s_eng_bufs[e].addr_mode == ADDR_MODE_HOST_PHYSICAL) && !s_is_ase)
    {
#ifndef FPGA_NEAR_MEM_MAP
        fprintf(stderr,
                "Port requires physical addresses. Please install the fpga_near_mem_map\n"
                "device driver from the OPAE intel-fpga-bbb repository, compile and install\n"
                "the intel-fpga-bbb software with -DBUILD_FPGA_NEAR_MEM_MAP=ON and compile\n"
                "this program with \"make FPGA_NEAR_MEM_MAP=1\".\n");
        exit(1);
#else
        // Call libfpga_near_mem_map from BBB repository for controller info.
        // At some point we will have to pass something other than 0 for the
        // controller number.
        uint64_t base_phys;
        numa_rd_mask = numa_allocate_nodemask();
        r = fpgaNearMemGetCtrlInfo(0, &base_phys, numa_rd_mask);
        numa_wr_mask = numa_rd_mask;
#endif
    }
    else
    {
        numa_rd_mask = numa_get_membind();
        numa_wr_mask = numa_get_membind();
    }
    s_eng_bufs[e].numa_rd_mem_mask = numa_rd_mask;
    s_eng_bufs[e].numa_wr_mem_mask = numa_wr_mask;

    // Separate 2MB read and write buffers
    s_eng_bufs[e].rd_buf = allocSharedBuffer(accel_handle, MB(2),
                                             s_eng_bufs[e].addr_mode,
                                             s_eng_bufs[e].numa_rd_mem_mask,
                                             &s_eng_bufs[e].rd_wsid,
                                             &s_eng_bufs[e].rd_buf_ioaddr);
    assert(NULL != s_eng_bufs[e].rd_buf);
    s_eng_bufs[e].rd_buf_ioaddr_enc = s_eng_bufs[e].rd_buf_ioaddr / s_eng_bufs[e].data_bus_bytes;
    printf("#  Engine %d read buffer: VA %p, DMA address %p\n", e,
           s_eng_bufs[e].rd_buf, (void*)s_eng_bufs[e].rd_buf_ioaddr);
    initReadBuf(s_eng_bufs[e].rd_buf, MB(2));
    // Flush to guarantee that the values reach RAM
    flushRange((void*)s_eng_bufs[e].rd_buf, MB(2));
    // Read back to the local cache. Some engine types may benefit from reading
    // cached memory. This doesn't undo the flushRange() above, which was needed
    // only to guarantee that RAM and cache are consistent.
    prefetchRange((void*)s_eng_bufs[e].rd_buf, MB(2));

    s_eng_bufs[e].wr_buf = allocSharedBuffer(accel_handle, MB(2),
                                             s_eng_bufs[e].addr_mode,
                                             s_eng_bufs[e].numa_wr_mem_mask,
                                             &s_eng_bufs[e].wr_wsid,
                                             &s_eng_bufs[e].wr_buf_ioaddr);
    assert(NULL != s_eng_bufs[e].wr_buf);
    s_eng_bufs[e].wr_buf_ioaddr_enc = s_eng_bufs[e].wr_buf_ioaddr / s_eng_bufs[e].data_bus_bytes;
    printf("#  Engine %d write buffer: VA %p, DMA address %p\n", e,
           s_eng_bufs[e].wr_buf, (void*)s_eng_bufs[e].wr_buf_ioaddr);

    // Will be determined later
    s_eng_bufs[e].fim_ifc_mhz = 0;

    // Set the buffer size mask. The buffer is 2MB but the mask covers
    // only 1MB. This allows bursts to flow a bit beyond the mask
    // without concern for overflow.
    csrEngWrite(csr_handle, accel_eng_idx, 4, (MB(1) / s_eng_bufs[e].data_bus_bytes) - 1);
}


// The same hash is implemented in the read path in the hardware.
static uint32_t
computeExpectedReadHash(
    uint16_t *buf,
    uint32_t line_bytes,
    uint32_t num_bursts,
    uint32_t burst_size)
{
    uint32_t hash = HASH32_DEFAULT_INIT;

    while (num_bursts--)
    {
        uint32_t num_lines = burst_size;
        while (num_lines--)
        {
            // Hash the low and high 16 bits of each line
            hash = hash32(hash, ((buf[line_bytes/2 - 1]) << 16) | buf[0]);
            buf += line_bytes/2;
        }
    }

    return hash;
}


// Checksum is used when hardware reads may arrive out of order.
static uint32_t
computeExpectedReadSum(
    uint16_t *buf,
    uint32_t line_bytes,
    uint32_t num_bursts,
    uint32_t burst_size)
{
    uint32_t sum = 0;

    while (num_bursts--)
    {
        uint32_t num_lines = burst_size;
        while (num_lines--)
        {
            // Hash the low and high 16 bits of each line
            sum += ((buf[line_bytes/2 - 1] << 16) | buf[0]);
            buf += line_bytes/2;
        }
    }

    return sum;
}


// Check a write buffer to confirm that the FPGA engine wrote the
// expected values.
static bool
testExpectedWrites(
    uint64_t *buf,
    uint64_t buf_ioaddr,
    uint32_t line_bytes,
    uint32_t num_bursts,
    uint32_t burst_size,
    uint32_t *line_index)
{
    *line_index = 0;

    while (num_bursts--)
    {
        uint32_t num_lines = burst_size;
        while (num_lines--)
        {
            // The low word is the IOADDR
            if (buf[0] != buf_ioaddr++) return false;
            // The high word is 0xdeadbeef
            if (buf[line_bytes/8 - 1] != 0xdeadbeef) return false;

            *line_index += 1;
            buf += line_bytes/8;
        }
    }

    // Confirm that the next line is 0. This is the first line not
    // written by the FPGA.
    if (buf[0] != 0) return false;
    if (buf[line_bytes/8 - 1] != 0) return false;

    return true;
}


static int
testMaskedWrite(
    uint32_t e
)
{
    int num_errors = 0;
    uint64_t emask = (uint64_t)1 << e;
    t_csr_handle_p csr_handle = s_eng_bufs[e].csr_handle;
    uint32_t line_bytes = s_eng_bufs[e].data_bus_bytes;

    // No support for masked writes?
    if (! s_eng_bufs[e].masked_writes)
    {
        printf("  Engine %d does not support masked writes\n", e);
        return 0;
    }

    // No read
    csrEngWrite(csr_handle, e, 0, 0);
    // Configure write
    csrEngWrite(csr_handle, e, 1, s_eng_bufs[e].wr_buf_ioaddr_enc);

    // Write 1 line (1 burst of 1 line)
    csrEngWrite(csr_handle, e, 2, ((uint64_t)1 << 32) | 1);
    csrEngWrite(csr_handle, e, 3, ((uint64_t)1 << 32) | 1);

    // Test a simple mask -- just prove that the mask reaches the FIM
    if (line_bytes == 32)
    {
        uint64_t mask = 0x3fffffe;
        csrEngWrite(csr_handle, e, 5, mask);
        printf("  Write engine %d, mask 0x%016" PRIx64 " - ", e, mask);
    }
    else if (line_bytes == 64)
    {
        uint64_t mask = 0x3fffffffffffffe;
        csrEngWrite(csr_handle, e, 5, mask);
        printf("  Write engine %d, mask 0x%016" PRIx64 " - ", e, mask);
    }
    else if (line_bytes == 128)
    {
        uint64_t mask_h = 0x3ffffffffffffff;
        csrEngWrite(csr_handle, e, 5, mask_h);
        uint64_t mask_l = 0xfffffffffffffffe;
        csrEngWrite(csr_handle, e, 5, mask_l);
        printf("  Write engine %d, mask 0x%016" PRIx64 "%016" PRIx64 " - ", e, mask_h, mask_l);
    }
    else
    {
        printf("FAIL: unsupported line size -- need to fix mask encoding\n");
        num_errors += 1;
    }

    // Set the line to all ones to make it easier to observe the mask
    memset((void*)s_eng_bufs[e].wr_buf, ~0, line_bytes);
    flushRange((void*)s_eng_bufs[e].wr_buf, line_bytes);

    // Start engine
    csrEnableEngines(csr_handle, emask);

    // Wait for it to start
    struct timespec wait_time;
    wait_time.tv_sec = 0;
    wait_time.tv_nsec = 1000000;
    while ((csrGetEnginesEnabled(csr_handle) == 0) ||
           csrGetEnginesActive(csr_handle))
    {
        nanosleep(&wait_time, NULL);
    }

    csrDisableEngines(csr_handle, emask);

    uint64_t *buf = (uint64_t*)s_eng_bufs[e].wr_buf;

    // Test expected values (assuming mask of 0x3fffffffffffffe)
    uint64_t buf_ioaddr = s_eng_bufs[e].wr_buf_ioaddr_enc;
    if (buf[0] != (buf_ioaddr | 0xff))
    {
        printf("FAIL (expected low 0x%016" PRIx64 ", found 0x%016" PRIx64 ")\n",
               buf_ioaddr | 0xff, buf[0]);
        num_errors += 1;
    }
    else if (buf[line_bytes/8 - 1] != 0xffffffffffffbeef)
    {
        printf("FAIL (expected high 0x%016" PRIx64 ", found 0x%016" PRIx64 ")\n",
               0xffffffffffffbeef, buf[line_bytes/8 - 1]);
        num_errors += 1;
    }
    else
    {
        printf("PASS\n");
    }

    // Clear the write mask
    csrEngWrite(csr_handle, e, 5, ~(uint64_t)0);

    return num_errors;
}


static int
testSmallRegions(
    uint32_t num_engines,
    uint64_t emask
)
{
    int num_errors = 0;

    // What is the maximum burst size for the engines? It is encoded in CSR 0.
    uint64_t max_burst_size = 1024;
    bool natural_bursts = false;
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        if (emask & ((uint64_t)1 << e))
        {
            if (max_burst_size > s_eng_bufs[e].max_burst_size)
                max_burst_size = s_eng_bufs[e].max_burst_size;

            natural_bursts |= s_eng_bufs[e].natural_bursts;
        }
    }

    printf("Testing emask 0x%lx, maximum burst size %ld:\n", emask, max_burst_size);

    uint64_t burst_size = 1;
    while (burst_size <= max_burst_size)
    {
        uint64_t num_bursts = 1;
        while (num_bursts < 100)
        {
            //
            // Test only reads (mode 1), only writes (mode 2) and
            // read+write (mode 3).
            //
            for (int mode = 1; mode <= 3; mode += 1)
            {
                for (uint32_t e = 0; e < num_engines; e += 1)
                {
                    t_csr_handle_p csr_handle = s_eng_bufs[e].csr_handle;

                    if (emask & ((uint64_t)1 << e))
                    {
                        // Read buffer base address (0 disables reads)
                        if (mode & 1)
                            csrEngWrite(csr_handle, e, 0, s_eng_bufs[e].rd_buf_ioaddr_enc);
                        else
                            csrEngWrite(csr_handle, e, 0, 0);

                        // Write buffer base address (0 disables writes)
                        if (mode & 2)
                            csrEngWrite(csr_handle, e, 1, s_eng_bufs[e].wr_buf_ioaddr_enc);
                        else
                            csrEngWrite(csr_handle, e, 1, 0);

                        // Clear the write buffer
                        memset((void*)s_eng_bufs[e].wr_buf, 0, MB(2));
                        flushRange((void*)s_eng_bufs[e].wr_buf, MB(2));

                        // Configure engine burst details
                        csrEngWrite(csr_handle, e, 2,
                                    (num_bursts << 32) | burst_size);
                        csrEngWrite(csr_handle, e, 3,
                                    (num_bursts << 32) | burst_size);
                    }
                }

                char *mode_str = "R+W:  ";
                if (mode == 1)
                    mode_str = "Read: ";
                if (mode == 2)
                {
                    mode_str = "Write:";
                }

                printf("  %s %2ld bursts of %2ld lines", mode_str,
                       num_bursts, burst_size);

                // Start your engines
                csrEnableEngines(s_eng_bufs[0].csr_handle, emask);

                // Wait for engine to complete. Checking csrGetEnginesEnabled()
                // resolves a race between the request to start an engine
                // and the engine active flag going high. Execution is done when
                // the engine is enabled and the active flag goes low.
                struct timespec wait_time;
                wait_time.tv_sec = 0;
                wait_time.tv_nsec = 1000000;
                uint64_t wait_nsec = 0;
                while ((csrGetEnginesEnabled(s_eng_bufs[0].csr_handle) == 0) ||
                       csrGetEnginesActive(s_eng_bufs[0].csr_handle))
                {
                    nanosleep(&wait_time, NULL);

                    wait_nsec += wait_time.tv_nsec + wait_time.tv_sec * (uint64_t)1000000000L;
                    if ((wait_nsec / (uint64_t)1000000000L) > (s_is_ase ? 20 : 5))
                    {
                        engineErrorAndExit(num_engines, emask);
                    }
                }

                // Stop the engine
                csrDisableEngines(s_eng_bufs[0].csr_handle, emask);

                bool pass = true;
                for (uint32_t e = 0; e < num_engines; e += 1)
                {
                    t_csr_handle_p csr_handle = s_eng_bufs[e].csr_handle;

                    if (emask & ((uint64_t)1 << e))
                    {
                        // Compute the expected hash and sum
                        uint32_t expected_hash = 0;
                        uint32_t expected_sum = 0;
                        if (mode & 1)
                        {
                            expected_hash = computeExpectedReadHash(
                                (uint16_t*)s_eng_bufs[e].rd_buf,
                                s_eng_bufs[e].data_bus_bytes,
                                num_bursts, burst_size);

                            expected_sum = computeExpectedReadSum(
                                (uint16_t*)s_eng_bufs[e].rd_buf,
                                s_eng_bufs[e].data_bus_bytes,
                                num_bursts, burst_size);
                        }

                        // Get the actual hash
                        uint32_t actual_hash = 0;
                        uint32_t actual_sum = 0;
                        if (mode & 1)
                        {
                            uint64_t check_val = csrEngRead(csr_handle, e, 5);
                            actual_hash = (uint32_t)check_val;
                            actual_sum = check_val >> 32;
                        }

                        // Test that writes arrived
                        bool writes_ok = true;
                        uint32_t write_error_line;
                        if (mode & 2)
                        {
                            flushRange((void*)s_eng_bufs[e].wr_buf, MB(2));

                            writes_ok = testExpectedWrites(
                                (uint64_t*)s_eng_bufs[e].wr_buf,
                                s_eng_bufs[e].wr_buf_ioaddr_enc,
                                s_eng_bufs[e].data_bus_bytes,
                                num_bursts, burst_size, &write_error_line);
                        }

                        if (expected_sum != actual_sum)
                        {
                            pass = false;
                            num_errors += 1;
                            printf("\n - FAIL %d: read ERROR expected sum 0x%08x found 0x%08x\n",
                                   e, expected_sum, actual_sum);
                            engineErrorAndExit(num_engines, emask);
                        }
                        else if ((expected_hash != actual_hash) &&
                                 s_eng_bufs[e].ordered_read_responses)
                        {
                            pass = false;
                            num_errors += 1;
                            printf("\n - FAIL %d: read ERROR expected hash 0x%08x found 0x%08x\n",
                                   e, expected_hash, actual_hash);
                            engineErrorAndExit(num_engines, emask);
                        }
                        else if (! writes_ok)
                        {
                            pass = false;
                            num_errors += 1;
                            printf("\n - FAIL %d: write ERROR line index 0x%x\n", e, write_error_line);
                        }
                    }
                }

                if (pass) printf(" - PASS\n");
            }

            num_bursts = (num_bursts * 2) + 1;
        }

        if (natural_bursts)
        {
            // Natural burst sizes -- test powers of 2
            burst_size <<= 1;
        }
        else
        {
            // Test every burst size up to 4 and then sparsely after that
            if ((burst_size < 4) || (burst_size == max_burst_size))
                burst_size += 1;
            else
            {
                burst_size = burst_size * 3 + 1;
                if (burst_size > max_burst_size) burst_size = max_burst_size;
            }
        }
    }

    return num_errors;
}


//
// Configure (but don't start) a continuous bandwidth test on one engine.
//
static int
configBandwidth(
    uint32_t glob_e,
    uint32_t burst_size,
    uint32_t mode,         // 1 - read, 2 - write, 3 - read+write
    uint32_t max_active    // Maximum outstanding requests at once (0 is unlimited)
)
{
    t_csr_handle_p csr_handle = s_eng_bufs[glob_e].csr_handle;
    // Map to local engine index
    uint32_t e = s_eng_bufs[glob_e].accel_eng_idx;

    // Read buffer base address (0 disables reads)
    if (mode & 1)
        csrEngWrite(csr_handle, e, 0, s_eng_bufs[glob_e].rd_buf_ioaddr_enc);
    else
        csrEngWrite(csr_handle, e, 0, 0);

    // Write buffer base address (0 disables writes)
    if (mode & 2)
        csrEngWrite(csr_handle, e, 1, s_eng_bufs[glob_e].wr_buf_ioaddr_enc);
    else
        csrEngWrite(csr_handle, e, 1, 0);

    // Configure engine burst details
    csrEngWrite(csr_handle, e, 2, ((uint64_t)max_active << 48) | burst_size);
    csrEngWrite(csr_handle, e, 3, ((uint64_t)max_active << 48) | burst_size);

    return 0;
}


//
// Run a bandwidth test (configured already with configBandwidth) on the set
// of engines indicated by emask.
//
static int
runBandwidth(
    uint32_t num_engines,
    uint64_t emask
)
{
    assert(emask != 0);

    // Start engines. In some modes, there may be multiple accelerator controllers
    // connected. Enable them all.
    t_csr_handle_p csr_handle = NULL;
    for (uint32_t c = 0; c < num_engines; c += 1)
    {
        if (s_eng_bufs[c].csr_handle != csr_handle)
        {
            csr_handle = s_eng_bufs[c].csr_handle;
            csrEnableEngines(csr_handle, emask);
        }
    }

    // Wait for them to start.
    struct timespec wait_time;
    wait_time.tv_sec = 0;
    wait_time.tv_nsec = 1000000;
    while (csrGetEnginesEnabled(s_eng_bufs[num_engines-1].csr_handle) == 0)
    {
        nanosleep(&wait_time, NULL);
    }

    // Let them run for a while
    usleep(s_is_ase ? 10000000 : 100000);
    
    csr_handle = NULL;
    for (uint32_t c = 0; c < num_engines; c += 1)
    {
        if (s_eng_bufs[c].csr_handle != csr_handle)
        {
            csr_handle = s_eng_bufs[c].csr_handle;
            csrDisableEngines(csr_handle, emask);
        }
    }

    // Wait for them to stop
    csr_handle = NULL;
    for (uint32_t c = 0; c < num_engines; c += 1)
    {
        if (s_eng_bufs[c].csr_handle != csr_handle)
        {
            csr_handle = s_eng_bufs[c].csr_handle;
            while (csrGetEnginesActive(csr_handle))
            {
                nanosleep(&wait_time, NULL);
            }
        }
    }

    if (s_afu_mhz == 0)
    {
        s_afu_mhz = csrGetClockMHz(s_eng_bufs[0].csr_handle);
    }

    return 0;
}


//
// Print bandwidth results after runBandwidth().
//
static int
printBandwidth(
    uint32_t num_engines,
    uint64_t emask
)
{
    assert(emask != 0);

    uint64_t cycles = csrGetClockCycles(s_eng_bufs[0].csr_handle);
    uint64_t read_bytes = 0;
    uint64_t write_bytes = 0;
    for (uint32_t glob_e = 0; glob_e < num_engines; glob_e += 1)
    {
        t_csr_handle_p csr_handle = s_eng_bufs[glob_e].csr_handle;
        uint32_t e = s_eng_bufs[glob_e].accel_eng_idx;

        if (emask & ((uint64_t)1 << glob_e))
        {
            read_bytes += csrEngRead(csr_handle, e, 2) * s_eng_bufs[glob_e].data_bus_bytes;
            write_bytes += csrEngRead(csr_handle, e, 3) * s_eng_bufs[glob_e].data_bus_bytes;
        }
    }

    if (!read_bytes && !write_bytes)
    {
        printf("  FAIL: no memory traffic detected!\n");
        return 1;
    }

    double read_bw = read_bytes * s_afu_mhz / (1000.0 * cycles);
    double write_bw = write_bytes * s_afu_mhz / (1000.0 * cycles);

    if (! write_bytes)
    {
        printf("  Read GB/s:  %0.2f\n", read_bw);
    }
    else if (! read_bytes)
    {
        printf("  Write GB/s: %0.2f\n", write_bw);
    }
    else
    {
        printf("  R+W GB/s:   %0.2f (read %0.2f, write %0.2f)\n",
               read_bw + write_bw, read_bw, write_bw);
    }

    return 0;
}


//
// Print bandwidth results after runBandwidth().
//
static int
printLatencyAndBandwidth(
    uint32_t num_engines,
    uint64_t emask,
    uint32_t max_active_reqs,
    uint32_t n_sampled_rd_engines,
    uint32_t n_sampled_wr_engines,
    bool print_header
)
{
    assert(emask != 0);

    uint64_t cycles = csrGetClockCycles(s_eng_bufs[0].csr_handle);
    double afu_ns_per_cycle = 1000.0 / s_afu_mhz;

    uint64_t total_read_bytes = 0;
    uint64_t total_write_bytes = 0;
    double read_avg_lat = 0;
    double fim_read_avg_lat = 0;
    double write_avg_lat = 0;
    uint64_t max_reads_in_flight = 0;
    uint64_t fim_max_reads_in_flight = 0;

    uint64_t eng_read_bytes[32];
    uint64_t eng_write_bytes[32];
    assert(num_engines < 32);

    // How many engines are being sampled in this test?
    uint32_t n_sampled_engines = 0;
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        if (emask & ((uint64_t)1 << e))
        {
            n_sampled_engines += 1;
        }
    }

    for (uint32_t glob_e = 0; glob_e < num_engines; glob_e += 1)
    {
        t_csr_handle_p csr_handle = s_eng_bufs[glob_e].csr_handle;
        uint32_t e = s_eng_bufs[glob_e].accel_eng_idx;

        if (emask & ((uint64_t)1 << glob_e))
        {
            // Is the engine's FIM frequency known yet?
            if (0 == s_eng_bufs[glob_e].fim_ifc_mhz)
            {
                uint64_t fim_clk_cycles = csrEngRead(csr_handle, e, 14);
                uint64_t eng_clk_cycles = csrEngRead(csr_handle, e, 15);
                s_eng_bufs[glob_e].fim_ifc_mhz = s_afu_mhz * fim_clk_cycles / eng_clk_cycles;
                printf("# FIM %d interface MHz: %0.1f\n", glob_e, s_eng_bufs[glob_e].fim_ifc_mhz);
            }
            double fim_ns_per_cycle = 1000.0 / s_eng_bufs[glob_e].fim_ifc_mhz;

            // Count of lines read and written by the engine
            uint64_t read_bytes = csrEngRead(csr_handle, e, 2) * s_eng_bufs[glob_e].data_bus_bytes;
            eng_read_bytes[glob_e] = read_bytes;
            total_read_bytes += read_bytes;
            uint64_t write_bytes = csrEngRead(csr_handle, e, 3) * s_eng_bufs[glob_e].data_bus_bytes;
            eng_write_bytes[glob_e] = write_bytes;
            total_write_bytes += write_bytes;

            // Total active lines across all cycles, from the AFU
            uint64_t read_active_bytes = csrEngRead(csr_handle, e, 8) * s_eng_bufs[glob_e].data_bus_bytes;
            uint64_t write_active_bytes = csrEngRead(csr_handle, e, 9) * s_eng_bufs[glob_e].data_bus_bytes;

            // Compute average latency using Little's Law. Each sampled engine
            // is given equal weight.
            if (read_bytes)
            {
                read_avg_lat += afu_ns_per_cycle * (read_active_bytes / read_bytes) / n_sampled_rd_engines;
            }
            if (write_bytes)
            {
                write_avg_lat += afu_ns_per_cycle * (write_active_bytes / write_bytes) / n_sampled_wr_engines;
            }

            // Sample latency calculation for reads at the boundary to the FIM.
            // The separates the FIM latency from the PIM latency.
            uint64_t fim_reads = csrEngRead(csr_handle, e, 10);
            if (fim_reads >> 63)
            {
                fprintf(stderr, "ERROR: FIM read tracking request/response mismatch!\n");
                exit(1);
            }
            uint64_t fim_read_active = csrEngRead(csr_handle, e, 11);
            if (fim_reads)
            {
                fim_read_avg_lat += fim_ns_per_cycle * (fim_read_active / fim_reads) / n_sampled_rd_engines;
            }

            max_reads_in_flight += csrEngRead(csr_handle, e, 12);
            uint64_t fim_max_reads = csrEngRead(csr_handle, e, 13);
            if (fim_max_reads >> 63)
            {
                // Unit is DWORDs, not lines. Reduce to lines.
                fim_max_reads &= 0x7fffffffffffffffL;
                fim_max_reads /= 16;
            }
            fim_max_reads_in_flight += fim_max_reads;
        }
    }

    if (!total_read_bytes && !total_write_bytes)
    {
        fprintf(stderr, "  FAIL: no memory traffic detected!\n");
        return 1;
    }

    double read_bw = total_read_bytes * s_afu_mhz / (1000.0 * cycles);
    double write_bw = total_write_bytes * s_afu_mhz / (1000.0 * cycles);

    if (print_header)
    {
        printf("Read GB/s, Write GB/s, Read Inflight Lines Limit, Read Max Measured Inflight Lines, "
               "FIM Read Max Measured Inflight Lines, Write Inflight Lines Limit, "
               "Read Avg Latency ns, FIM Read Avg Latency ns, Write Avg Latency ns");

        if (num_engines > 1)
        {
            for (uint32_t glob_e = 0; glob_e < num_engines; glob_e += 1)
            {
                printf(", Eng%d Read GB/s, Eng%d Write GB/s", glob_e, glob_e);
            }
        }

        printf("\n");
    }

    printf("%0.2f %0.2f %d %ld %ld %d %0.0f %0.0f %0.0f",
           read_bw, write_bw,
           max_active_reqs, max_reads_in_flight, fim_max_reads_in_flight, max_active_reqs,
           read_avg_lat, fim_read_avg_lat, write_avg_lat);

    if (num_engines > 1)
    {
        for (uint32_t glob_e = 0; glob_e < num_engines; glob_e += 1)
        {
            double eng_read_bw = eng_read_bytes[glob_e] * s_afu_mhz / (1000.0 * cycles);
            double eng_write_bw = eng_write_bytes[glob_e] * s_afu_mhz / (1000.0 * cycles);
            printf(" %0.2f %0.2f", eng_read_bw, eng_write_bw);
        }
    }

    printf("\n");

    return 0;
}


int
testHostChanParams(
    int argc,
    char *argv[],
    fpga_handle accel_handle,
    t_csr_handle_p csr_handle,
    bool is_ase)
{
    int result = 0;
    s_is_ase = is_ase;

    printf("# Test ID: %016" PRIx64 " %016" PRIx64 " (%ld)\n",
           csrEngGlobRead(csr_handle, 1),
           csrEngGlobRead(csr_handle, 0),
           0xff & (csrEngGlobRead(csr_handle, 2) >> 24));

    uint32_t num_engines = csrGetNumEngines(csr_handle);
    printf("# Engines: %d\n", num_engines);

    // Allocate memory buffers for each engine
    s_eng_bufs = malloc(num_engines * sizeof(t_engine_buf));
    assert(NULL != s_eng_bufs);
    s_num_engines = num_engines;
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        initEngine(e, accel_handle, csr_handle, e);
    }
    printf("\n");

    // Test each engine separately
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        if (testSmallRegions(num_engines, (uint64_t)1 << e))
        {
            // Quit on error
            result = 1;
            goto done;
        }
    }

    // Test all the engines at once
    if (num_engines > 1)
    {
        if (testSmallRegions(num_engines, ((uint64_t)1 << num_engines) - 1))
        {
            // Quit on error
            result = 1;
            goto done;
        }
    }

    // Masked writes
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        printf("\nTesting masked writes:\n");
        if (testMaskedWrite(e))
        {
            // Quit on error
            result = 1;
            goto done;
        }
    }

    // Bandwidth test each engine individually
    bool printed_afu_mhz = false;
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        uint64_t burst_size = 1;
        while (burst_size <= s_eng_bufs[e].max_burst_size)
        {
            printf("\nTesting engine %d, burst size %ld:\n", e, burst_size);

            for (int mode = 1; mode <= 3; mode += 1)
            {
                configBandwidth(e, burst_size, mode, 0);
                runBandwidth(num_engines, (uint64_t)1 << e);

                if (! printed_afu_mhz)
                {
                    printf("  AFU clock is %.1f MHz\n", s_afu_mhz);
                    printed_afu_mhz = true;
                }

                printBandwidth(num_engines, (uint64_t)1 << e);
            }

            if (s_eng_bufs[e].natural_bursts)
            {
                // Natural burst sizes -- test powers of 2
                burst_size <<= 1;
            }
            else
            {
                burst_size += 1;
                if ((burst_size < s_eng_bufs[e].max_burst_size) && (burst_size == 9))
                {
                    burst_size = s_eng_bufs[e].max_burst_size;
                }
            }
        }
    }

    // Bandwidth test all engines together
    if (num_engines > 1)
    {
        printf("\nTesting all engines, max burst size:\n");

        for (int mode = 1; mode <= 3; mode += 1)
        {
            for (uint32_t e = 0; e < num_engines; e += 1)
            {
                configBandwidth(e, s_eng_bufs[e].max_burst_size, mode, 0);
            }
            runBandwidth(num_engines, ((uint64_t)1 << num_engines) - 1);
            printBandwidth(num_engines, ((uint64_t)1 << num_engines) - 1);
        }
    }

    // Release buffers
  done:
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        fpgaReleaseBuffer(accel_handle, s_eng_bufs[e].rd_wsid);
        fpgaReleaseBuffer(accel_handle, s_eng_bufs[e].wr_wsid);
    }

    return result;
}


int
testHostChanLatency(
    int argc,
    char *argv[],
    uint32_t num_accels,
    fpga_handle *accel_handles,
    t_csr_handle_p *csr_handles,
    bool is_ase,
    uint32_t engine_mask
)
{
    int result = 0;
    uint32_t num_engines = 0;
    s_is_ase = is_ase;

    for (uint32_t a = 0; a < num_accels; a += 1)
    {
        printf("# Test ID: %016" PRIx64 " %016" PRIx64 " (%ld)\n",
               csrEngGlobRead(csr_handles[a], 1),
               csrEngGlobRead(csr_handles[a], 0),
               0xff & (csrEngGlobRead(csr_handles[a], 2) >> 24));

        num_engines += csrGetNumEngines(csr_handles[a]);
    }

    printf("# Engines: %d\n", num_engines);

    // Limit incoming engine mask to available engines
    engine_mask &= (1 << num_engines) - 1;
    if (0 == engine_mask)
    {
        fprintf(stderr, "No engines selected!\n");
        return 1;
    }

    // Allocate memory buffers for each engine
    s_eng_bufs = malloc(num_engines * sizeof(t_engine_buf));
    assert(NULL != s_eng_bufs);
    s_num_engines = num_engines;
    uint64_t max_burst_size = 8;
    bool natural_bursts = false;
    uint32_t glob_e = 0;
    for (uint32_t a = 0; a < num_accels; a += 1)
    {
        uint32_t accel_num_engines = csrGetNumEngines(csr_handles[a]);
        for (uint32_t e = 0; e < accel_num_engines; e += 1)
        {
            initEngine(glob_e, accel_handles[a], csr_handles[a], e);

            if (max_burst_size > s_eng_bufs[glob_e].max_burst_size)
                max_burst_size = s_eng_bufs[glob_e].max_burst_size;

            natural_bursts |= s_eng_bufs[glob_e].natural_bursts;

            glob_e += 1;
        }
    }

    // Bandwidth test each engine individually
    bool printed_afu_mhz = false;
    uint64_t burst_size = 1;

    int max_mode = 3;
    if (num_accels > 1) max_mode = 5;
    if (num_accels > 2) max_mode = 6;

    while (burst_size <= max_burst_size)
    {
        for (int mode = 1; mode <= max_mode; mode += 1)
        {
            bool printed_header = false;
            for (uint32_t max_reqs = burst_size; max_reqs <= 608; max_reqs = (max_reqs + 4) & 0xfffffffc)
            {
                uint32_t num_readers = 0;
                uint32_t num_writers = 0;

                for (uint32_t e = 0; e < num_engines; e += 1)
                {
                    if (engine_mask & (1 << e))
                    {
                        int eng_mode = mode;
                        if (mode == 4)
                            // Only engine 0 read, all others write
                            eng_mode = (e == 0) ? 1 : 2;
                        else if (mode == 5)
                            // Only engine 0 read, all others read+write
                            eng_mode = (e == 0) ? 1 : 3;
                        else if (mode == 6)
                            // Only engine 0 write, all others read
                            eng_mode = (e == 0) ? 2 : 1;

                        configBandwidth(e, burst_size, eng_mode, max_reqs);
                        if (eng_mode & 1)
                        {
                            num_readers += 1;
                            prefetchRange((void*)s_eng_bufs[e].rd_buf, MB(2));
                        }
                        if (eng_mode & 2)
                        {
                            num_writers += 1;
                            flushRange((void*)s_eng_bufs[e].wr_buf, MB(2));
                        }
                    }

                }

                runBandwidth(num_engines, engine_mask);

                if (! printed_afu_mhz)
                {
                    printf("# AFU MHz: %.1f\n", s_afu_mhz);
                    printed_afu_mhz = true;
                }

                if (! printed_header)
                {
                    printf("\n\n# Engine mask: %d\n", engine_mask);
                    printf("# Burst size: %ld\n", burst_size);
                    printf("# Mode: ");
                    if (mode == 1) printf("read\n");
                    else if (mode == 2) printf("write\n");
                    else if (mode == 3) printf("read+write\n");
                    else if (mode == 4) printf("one read+others write\n");
                    else if (mode == 5) printf("one read+others read+write\n");
                    else printf("one write+others read\n");
                }

                printLatencyAndBandwidth(num_engines, engine_mask, max_reqs,
                                         num_readers, num_writers,
                                         ! printed_header);

                printed_header = true;
            }
        }

        if (! natural_bursts)
            burst_size += 1;
        else
            burst_size <<= 1;
    }

    // Release buffers
  done:
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        fpgaReleaseBuffer(s_eng_bufs[e].accel_handle, s_eng_bufs[e].rd_wsid);
        fpgaReleaseBuffer(s_eng_bufs[e].accel_handle, s_eng_bufs[e].wr_wsid);
    }

    return result;
}
