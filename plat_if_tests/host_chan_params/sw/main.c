// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <inttypes.h>
#include <assert.h>
#include <getopt.h>

#include <opae/fpga.h>

// State from the AFU's JSON file, extracted using OPAE's afu_json_mgr script
#include "afu_json_info.h"
#include "tests_common.h"
#include "test_host_chan_params.h"

static t_target_bdf target;
static bool latency_mode;
static uint32_t latency_engine_mask;

const uint32_t max_allowed_accels = 16;
static uint32_t max_accels = 1;

//
// Print help
//
static void
help(void)
{
    printf("\n"
           "Usage:\n"
           "    host_chan_params [-h] [-B <bus>] [-D <device>] [-F <function>] [-S <socket-id>]\n"
           "                     [--latency=<engine mask>]\n"
           "\n"
           "        -h,--help           Print this help\n"
           "        -B,--bus            Set target bus number\n"
           "        -D,--device         Set target device number\n"
           "        -F,--function       Set target function number\n"
           "        -S,--socket-id      Set target socket number\n"
           "        --segment           Set target segment number\n"
           "\n"
           "        --latency           Run latency/bandwidth tests.\n"
           "                            With no arguments, run on all available engines.\n"
           "                            An optional numeric bitmask selects engines.\n"
           "                            E.g., 6 skips engine 0 and runs engines 2 and 3.\n"
           "        --max-accels        Maximum number of accelerators to open. An\n"
           "                            accelerator is a unique AFU. This parameter is\n"
           "                            relevant only in --latency mode.\n"
           "\n");
}


//
// Parse command line arguments
//
#define GETOPT_STRING ":hB:D:F:S:"
static int
parse_args(int argc, char *argv[])
{
    struct option longopts[] = {
        {"help",       no_argument,       NULL, 'h'},
        {"bus",        required_argument, NULL, 'B'},
        {"device",     required_argument, NULL, 'D'},
        {"function",   required_argument, NULL, 'F'},
        {"socket-id",  required_argument, NULL, 'S'},
        {"segment",    required_argument, NULL, 0xe},
        {"latency",    optional_argument, NULL, 0xf},
        {"max-accels", required_argument, NULL, 0x10},
        {0, 0, 0, 0}
    };

    int getopt_ret;
    int option_index;
    char *endptr = NULL;

    while (-1
           != (getopt_ret = getopt_long(argc, argv, GETOPT_STRING, longopts,
                        &option_index))) {
        const char *tmp_optarg = optarg;

        if ((optarg) && ('=' == *tmp_optarg)) {
            ++tmp_optarg;
        }

        switch (getopt_ret) {
        case 'h': /* help */
            help();
            return -1;

        case 0xe: /* segment */
            if (NULL == tmp_optarg)
                break;
            endptr = NULL;
            target.segment =
                (int)strtoul(tmp_optarg, &endptr, 0);
            if (endptr != tmp_optarg + strlen(tmp_optarg)) {
                fprintf(stderr, "invalid segment: %s\n",
                    tmp_optarg);
                return -1;
            }
            break;

        case 0xf: /* latency mode */
            latency_mode = true;

            if (NULL == tmp_optarg)
            {
                latency_engine_mask = ~0;
            }
            else
            {
                endptr = NULL;
                latency_engine_mask =
                    (uint32_t)strtoul(tmp_optarg, &endptr, 0);
                if (endptr != tmp_optarg + strlen(tmp_optarg)) {
                    fprintf(stderr, "invalid latency engine mask: %s\n",
                            tmp_optarg);
                    return -1;
                }
            }
            break;

        case 0x10: /* max-accels */
            if (NULL == tmp_optarg)
                break;
            endptr = NULL;
            max_accels =
                (int)strtoul(tmp_optarg, &endptr, 0);
            if (endptr != tmp_optarg + strlen(tmp_optarg)) {
                fprintf(stderr, "invalid number of accelerators: %s\n",
                    tmp_optarg);
                return -1;
            }
            if (max_accels > max_allowed_accels) {
                fprintf(stderr, "number of accelerators exceeds %d\n",
                        max_allowed_accels);
                return -1;
            }
            break;

        case 'B': /* bus */
            if (NULL == tmp_optarg)
                break;
            endptr = NULL;
            target.bus =
                (int)strtoul(tmp_optarg, &endptr, 0);
            if (endptr != tmp_optarg + strlen(tmp_optarg)) {
                fprintf(stderr, "invalid bus: %s\n",
                    tmp_optarg);
                return -1;
            }
            break;

        case 'D': /* device */
            if (NULL == tmp_optarg)
                break;
            endptr = NULL;
            target.device =
                (int)strtoul(tmp_optarg, &endptr, 0);
            if (endptr != tmp_optarg + strlen(tmp_optarg)) {
                fprintf(stderr, "invalid device: %s\n",
                    tmp_optarg);
                return -1;
            }
            break;

        case 'F': /* function */
            if (NULL == tmp_optarg)
                break;
            endptr = NULL;
            target.function =
                (int)strtoul(tmp_optarg, &endptr, 0);
            if (endptr != tmp_optarg + strlen(tmp_optarg)) {
                fprintf(stderr, "invalid function: %s\n",
                    tmp_optarg);
                return -1;
            }
            break;

        case 'S': /* socket */
            if (NULL == tmp_optarg)
                break;
            endptr = NULL;
            target.socket =
                (int)strtoul(tmp_optarg, &endptr, 0);
            if (endptr != tmp_optarg + strlen(tmp_optarg)) {
                fprintf(stderr, "invalid socket: %s\n",
                    tmp_optarg);
                return -1;
            }
            break;

        case ':': /* missing option argument */
            fprintf(stderr, "Missing option argument\n");
            return -1;

        case '?':
        default: /* invalid option */
            fprintf(stderr, "Invalid cmdline options. Use --help.\n");
            return -1;
        }
    }

    if (optind != argc) {
        fprintf(stderr, "Unexpected extra arguments\n");
        return -1;
    }

    return 0;
}


int main(int argc, char *argv[])
{
    fpga_result r;
    fpga_handle accel_handles[max_allowed_accels];
    t_csr_handle_p csr_handles[max_allowed_accels];
    uint32_t num_accels;

    initTargetBDF(&target);
    if (parse_args(argc, argv) < 0)
        return 1;

    // Find and connect to the accelerator(s)
    num_accels = max_accels;
    r = connectToMatchingAccels(AFU_ACCEL_UUID, &target,
                                &num_accels, accel_handles);
    assert(FPGA_OK == r);
    if (0 == num_accels) return 0;
    bool is_ase = probeForASE(&target);
    if (is_ase)
    {
        printf("# Running in ASE mode\n");
    }

    for (uint32_t a = 0; a < num_accels; a += 1)
    {
        csr_handles[a] = csrAllocHandle(accel_handles[a], 0);
        assert(csr_handles[a] != NULL);

        printf("# AFU ID:  %016" PRIx64 " %016" PRIx64 " (%d)\n",
               csrRead(csr_handles[a], CSR_AFU_ID_H),
               csrRead(csr_handles[a], CSR_AFU_ID_L),
               a);
    }

    // Run tests
    int status;
    if (! latency_mode)
    {
        status = testHostChanParams(argc, argv, accel_handles[0], csr_handles[0], is_ase);
    }
    else
    {
        status = testHostChanLatency(argc, argv, num_accels, accel_handles, csr_handles, is_ase,
                                     latency_engine_mask);
    }

    // Done
    for (uint32_t a = 0; a < num_accels; a += 1)
    {
        csrReleaseHandle(csr_handles[a]);
        fpgaClose(accel_handles[a]);
    }

    return status;
}
