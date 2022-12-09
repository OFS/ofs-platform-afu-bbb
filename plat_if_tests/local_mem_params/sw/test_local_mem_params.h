// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifndef __TEST_LOCAL_MEM_PARAMS_H__
#define __TEST_LOCAL_MEM_PARAMS_H__

#include <opae/fpga.h>
#include "tests_common.h"

int
testLocalMemParams(
    int argc,
    char *argv[],
    fpga_handle accel_handle,
    t_csr_handle_p csr_handle,
    bool is_ase);

#endif // __TEST_LOCAL_MEM_PARAMS_H__
