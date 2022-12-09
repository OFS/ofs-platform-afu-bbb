// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifndef __HASH32_H__
#define __HASH32_H__

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

extern const uint32_t HASH32_DEFAULT_INIT;

// This code matches the hash32 RTL. It isn't fast.
uint32_t hash32(uint32_t cur_hash, uint32_t data);

#ifdef __cplusplus
}
#endif
#endif // __HASH32_H__
