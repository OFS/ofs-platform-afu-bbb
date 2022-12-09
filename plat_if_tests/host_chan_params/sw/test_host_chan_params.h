// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifndef __TEST_HOST_CHAN_PARAMS_H__
#define __TEST_HOST_CHAN_PARAMS_H__

#include <opae/fpga.h>
#include "tests_common.h"

int
testHostChanParams(
    int argc,
    char *argv[],
    fpga_handle accel_handle,
    t_csr_handle_p csr_handle,
    bool is_ase);

int
testHostChanLatency(
    int argc,
    char *argv[],
    uint32_t num_accels,
    fpga_handle *accel_handles,
    t_csr_handle_p *csr_handles,
    bool is_ase,
    uint32_t engine_mask);

#endif // __TEST_HOST_CHAN_PARAMS_H__
