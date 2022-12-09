// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifndef __TEST_HOST_CHAN_ATOMIC_H__
#define __TEST_HOST_CHAN_ATOMIC_H__

#include <opae/fpga.h>
#include "tests_common.h"

int
testHostChanAtomic(
    int argc,
    char *argv[],
    fpga_handle accel_handle,
    t_csr_handle_p csr_handle,
    bool is_ase,
    bool verbose);

#endif // __TEST_HOST_CHAN_ATOMIC_H__
