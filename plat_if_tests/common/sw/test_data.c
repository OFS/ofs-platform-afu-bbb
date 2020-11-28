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
// Write test data generator and read check hash functions.
//

#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include "test_data.h"
#include "hash32.h"

static void
assert_valid_len(size_t byte_len)
{
    // Size must be a multiple of 8 bytes
    assert(0 == (byte_len & 7));

    // Size must be at least 8 bytes
    assert(byte_len >= 8);
}
    

//
// Reset the generator's data vector to the initial value. A 64 bit seed
// is XORed into every 64 bit word, allowing the caller to vary the
// generated values.
//
void
testDataGenReset(size_t byte_len, uint64_t seed, uint64_t *data)
{
    assert_valid_len(byte_len);

    static const uint64_t init_data[8] = {
        0x860761722b164a00,
        0x54de0dc97b564cbf,
        0x8519a51b2767a2fa,
        0x33b23fb3ab3c4277,
        0xafcc6ba3db67f2b3,
        0x76655f3e9ba84438,
        0xb173761f0b5a083b,
        0x8644554624594bbf
        };

    // Copy init_data to the target
    size_t i_byte_len = byte_len;
    uint64_t *i_data = data;
    while (i_byte_len)
    {
        size_t len = (i_byte_len > 64) ? 64 : i_byte_len;
        memcpy(i_data, init_data, len);

        i_data += (len / 8);
        i_byte_len -= len;
    }

    // XOR the seed in every entry. The seed is rotated one bit for
    // each entry since otherwise it cancels itself out when the
    // hashes are reduced.
    for (size_t i = 0; i < (byte_len / 8); i += 1)
    {
        data[i] ^= seed;
        seed = (seed << 1) | (seed >> 63);
    }
}


//
// Generate the next data vector (presumably following a write)
//
void
testDataGenNext(size_t byte_len, uint64_t seed, uint64_t *data)
{
    assert_valid_len(byte_len);

    // Each 64 bit entry is rotated one byte left and XOR the seed in
    for (size_t i = 0; i < (byte_len / 8); i += 1)
    {
        data[i] = (data[i] << 8) | (data[i] >> 56);
        data[i] ^= seed;
        seed = (seed << 1) | (seed >> 63);
    }
}


//
// Initialize the hash buckets. The vector of buckets should be the
// same byte length as the data itself.
//
void
testDataChkReset(size_t byte_len, void *hash_vec)
{
    assert_valid_len(byte_len);

    uint32_t *hash_buckets = (uint32_t*)hash_vec;

    for (size_t i = 0; i < (byte_len / 4); i += 1)
    {
        hash_buckets[i] = HASH32_DEFAULT_INIT;
    }
}


//
// Update hashes with new data.
//
void
testDataChkNext(size_t byte_len, void *hash_vec, uint64_t *data)
{
    assert_valid_len(byte_len);

    uint32_t *hash_buckets = (uint32_t*)hash_vec;
    // Treat data as 32 bit values
    uint32_t *data32 = (uint32_t*)data;

    for (size_t i = 0; i < (byte_len / 4); i += 1)
    {
        hash_buckets[i] = hash32(hash_buckets[i], data32[i]);
    }
}


//
// Reduce hashes to a single 64 bit value.
//
uint64_t
testDataChkReduce(size_t byte_len, void *hash_vec)
{
    // hash_vec is a vector of 32 bit hash values. Here, we group the
    // hash values in two buckets. Each group is XORed to reduce
    // it to a single 32 bit check value. The two 32 bit check values
    // are merged to form the 64 bit result.
    assert_valid_len(byte_len);

    uint32_t *hash_buckets = (uint32_t*)hash_vec;
    uint32_t hash_low = 0;
    uint32_t hash_high = 0;
    size_t high_idx = byte_len / 8;

    for (size_t i = 0; i < high_idx; i += 1)
    {
        hash_low ^= hash_buckets[i];
        hash_high ^= hash_buckets[high_idx + i];
    }

    return ((uint64_t)hash_high << 32) | hash_low;
}


//
// Convenience function to generate a reduced hash for num_data_values
// and a seed. This tends to be useful when synthesizing check data
// to compare with the hardware. It drives testDataGen functions to
// synthesize data and testDataChk functions to compute the associated
// hash.
//
uint64_t
testDataChkGen(size_t byte_len, uint64_t seed, int num_data_values)
{
    assert_valid_len(byte_len);

    uint64_t *data = malloc(byte_len);
    uint64_t *hash_vec = malloc(byte_len);
    assert((data != NULL) && (hash_vec != NULL));

    testDataGenReset(byte_len, seed, data);
    testDataChkReset(byte_len, hash_vec);

    for (int i = 0; i < num_data_values; i += 1)
    {
        testDataChkNext(byte_len, hash_vec, data);
        testDataGenNext(byte_len, seed, data);
    }

    uint64_t chk = testDataChkReduce(byte_len, hash_vec);

    free(hash_vec);
    free(data);

    return chk;
}
