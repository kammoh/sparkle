///////////////////////////////////////////////////////////////////////////////
// encrypt.c: Optimized C99 implementation of the AEAD algorithm SCHWAEMM.   //
// This file is part of the SPARKLE submission to NIST's LW Crypto Project.  //
// Version 1.1.2 (2020-10-30), see <http://www.cryptolux.org/> for updates.  //
// Authors: The SPARKLE Group (C. Beierle, A. Biryukov, L. Cardoso dos       //
// Santos, J. Groszschaedl, L. Perrin, A. Udovenko, V. Velichkov, Q. Wang).  //
// License: GPLv3 (see LICENSE file), other licenses available upon request. //
// Copyright (C) 2019-2020 University of Luxembourg <http://www.uni.lu/>.    //
// ------------------------------------------------------------------------- //
// This program is free software: you can redistribute it and/or modify it   //
// under the terms of the GNU General Public License as published by the     //
// Free Software Foundation, either version 3 of the License, or (at your    //
// option) any later version. This program is distributed in the hope that   //
// it will be useful, but WITHOUT ANY WARRANTY; without even the implied     //
// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the  //
// GNU General Public License for more details. You should have received a   //
// copy of the GNU General Public License along with this program. If not,   //
// see <http://www.gnu.org/licenses/>.                                       //
///////////////////////////////////////////////////////////////////////////////

// This source code file should be compiled with the following set of flags:
// -std=c99 -Wall -Wextra -Wshadow -fsanitize=address,undefined -O2

// gencat_aead.c shall be used to generate the test vector output file. The
// test vector output file shall be provided in the corresponding
// crypto_aead/[algorithm]/ directory

#include <stddef.h> // for size_t
#include <string.h> // for memcpy, memset
#include "schwaemm_cfg.h"
#include "sparkle_opt.h"

typedef unsigned char UChar;
typedef unsigned long long int ULLInt;

#define KEY_WORDS (SCHWAEMM_KEY_LEN / 32)
#define KEY_BYTES (SCHWAEMM_KEY_LEN / 8)
#define NONCE_WORDS (SCHWAEMM_NONCE_LEN / 32)
#define NONCE_BYTES (SCHWAEMM_NONCE_LEN / 8)
#define TAG_WORDS (SCHWAEMM_TAG_LEN / 32)
#define TAG_BYTES (SCHWAEMM_TAG_LEN / 8)

#define STATE_BRANS (SPARKLE_STATE / 64)
#define STATE_WORDS (SPARKLE_STATE / 32)
#define STATE_BYTES (SPARKLE_STATE / 8)
#define RATE_BRANS (SPARKLE_RATE / 64)
#define RATE_WORDS (SPARKLE_RATE / 32)
#define RATE_BYTES (SPARKLE_RATE / 8)
#define CAP_BRANS (SPARKLE_CAPACITY / 64)
#define CAP_WORDS (SPARKLE_CAPACITY / 32)
#define CAP_BYTES (SPARKLE_CAPACITY / 8)

#define CONST_A0 (((uint32_t)(0 ^ (1 << CAP_BRANS))) << 24)
#define CONST_A1 (((uint32_t)(1 ^ (1 << CAP_BRANS))) << 24)
#define CONST_M2 (((uint32_t)(2 ^ (1 << CAP_BRANS))) << 24)
#define CONST_M3 (((uint32_t)(3 ^ (1 << CAP_BRANS))) << 24)

///////////////////////////////////////////////////////////////////////////////
/////// HELPER FUNCTIONS AND MACROS (RHO1, RHO2, RATE-WHITENING, ETC.) ////////
///////////////////////////////////////////////////////////////////////////////

// The plaintext, associated data, and ciphertext are stored in arrays of type
// unsigned char. Casting such an unsigned-char-pointer to an uint32_t-pointer
// increases alignment requirements, i.e. the start address of the array has to
// be even on 16-bit architectures or a multiple of four (i.e. 4-byte aligned)
// on 32-bit and 64-bit platforms. The following preprocessor statements help
// to determine the alignment requirements for a uint32_t pointer.

#define MIN_SIZE(a, b) ((sizeof(a) < sizeof(b)) ? sizeof(a) : sizeof(b))
#if defined(_MSC_VER) && !defined(__clang__) && !defined(__ICL)
#define UI32_ALIGN_BYTES MIN_SIZE(unsigned __int32, size_t)
#else
#include <stdint.h>
#define UI32_ALIGN_BYTES MIN_SIZE(uint32_t, uint_fast8_t)
#endif

// The rate-whitening for SCHWAEMM256_128 applies the "tweak" described in
// Section 2.3.2 of the specification. Therefore, the indices used to load the
// 32-bit words from the capacity-part of the state need to be reduced modulo
// CAP_WORDS, which the C implementation below does by ANDing the index with
// (CAP_WORDS - 1) = 3. Performing the modulo reduction in this way only works
// when CAP_WORDS is a power of 2, which is the case for SCHWAEMM256_128.

#if (RATE_WORDS > CAP_WORDS)
#define CAP_INDEX(i) ((i) & (CAP_WORDS - 1))
#else // RATE_WORDS <= CAP_WORDS
#define CAP_INDEX(i) (i)
#endif

int valid_bytes(int inlen_bytes, int word_index)
{
  int num_valid_bytes = inlen_bytes - word_index * 4;
  if (num_valid_bytes < 0)
    num_valid_bytes = 0;
  if (num_valid_bytes > 4)
    num_valid_bytes = 4;
  return (1 << num_valid_bytes) - 1;
}

uint32_t inbuf_word(int32_t inbuf_word, int32_t in_xor_state_word, int valid_bytes, int decrypt)
{
  uint32_t mask = 0;
  for (int i = 0; i < 4; i++)
  {
    if ((valid_bytes >> i) & 1)
      mask |= 0xff << (i * 8);
  }
  uint32_t word = inbuf_word;
  if (decrypt)
  {
    word = (mask & inbuf_word) | ((~mask) & in_xor_state_word);
  }

  return word;
}

static void rho_whi(uint32_t *state, uint8_t *out, const uint8_t *in, size_t inlen, int decrypt, int last, int aut)
{
  uint32_t inbuf[RATE_WORDS], outbuf[RATE_WORDS], in_xor_state[RATE_WORDS];
  int i;

  memcpy(inbuf, in, RATE_BYTES);

  if (inlen < RATE_BYTES)
  { // padding
    uint8_t *bufptr = ((uint8_t *)inbuf) + inlen;
    memset(bufptr, 0, (RATE_BYTES - inlen));
    *bufptr = 0x80;
  }
  if (last)
  {
    if (aut)
      state[STATE_WORDS - 1] ^= ((inlen < RATE_BYTES) ? CONST_A0 : CONST_A1);
    else
      state[STATE_WORDS - 1] ^= ((inlen < RATE_BYTES) ? CONST_M2 : CONST_M3);
  }

  for (i = 0; i < RATE_WORDS; i++)
  {
    in_xor_state[i] = state[i] ^ inbuf[i];
  }

  for (i = 0; i < RATE_WORDS / 2; i++)
  {
    int j = i + RATE_WORDS / 2;
    uint32_t in_word_l = inbuf_word(inbuf[i], in_xor_state[i], valid_bytes(inlen, i), decrypt);
    uint32_t in_word_r = inbuf_word(inbuf[j], in_xor_state[j], valid_bytes(inlen, j), decrypt);
    uint32_t z = state[j] ^ in_word_l ^ state[RATE_WORDS + i];
    uint32_t t = state[i] ^ in_word_r ^ state[RATE_WORDS + CAP_INDEX(j)];
    state[i] = decrypt ? state[i] ^ z : z;
    state[j] = decrypt ? t : state[j] ^ t;
    outbuf[i] = in_xor_state[i];
    outbuf[j] = in_xor_state[j];
  }

  if (out)
    memcpy(out, outbuf, RATE_BYTES);
}

///////////////////////////////////////////////////////////////////////////////
///////////// LOW-LEVEL AEAD FUNCTIONS (FOR USE WITH FELICS-AEAD) /////////////
///////////////////////////////////////////////////////////////////////////////

// The Initialize function loads nonce and key into the state and executes the
// SPARKLE permutation with the big number of steps.

void Initialize(uint32_t *state, const uint8_t *key, const uint8_t *nonce)
{
  // printf("CONST_A0=%02x CONST_A1=%02x CONST_M2=%02x CONST_M3=%02x\n", CONST_A0, CONST_A1, CONST_M2, CONST_M3);
  // exit(1);
  // load nonce into the rate-part of the state
  memcpy(state, nonce, NONCE_BYTES);
  // load key into the capacity-part of the sate
  memcpy((state + RATE_WORDS), key, KEY_BYTES);
  // execute SPARKLE with big number of steps
  sparkle_opt(state, STATE_BRANS, SPARKLE_STEPS_BIG);
}

// The ProcessPlainText function encrypts the plaintext (in blocks of size
// RATE_BYTES) and generates the respective ciphertext. The uint8_t-array 'in'
// contains the plaintext and the ciphertext is written to uint8_t-array 'out'
// ('in' and 'out' can be the same array, i.e. they can have the same start
// address). Note that this function MUST NOT be called when the length of the
// plaintext is 0.

void ProcessText(uint32_t *state, uint8_t *out, const uint8_t *in, size_t inlen, int aut, int dec)
{
  while (inlen > RATE_BYTES)
  {
    // combined Rho and rate-whitening operation
    rho_whi(state, out, in, inlen, dec, 0, aut);
    // execute SPARKLE with slim number of steps
    sparkle_opt(state, STATE_BRANS, SPARKLE_STEPS_SLIM);
    inlen -= RATE_BYTES;
    if (out)
      out += RATE_BYTES;
    in += RATE_BYTES;
  }

  rho_whi(state, out, in, inlen, dec, 1, aut);
  // combined Rho and rate-whitening (incl. padding)
  // execute SPARKLE with big number of steps
  sparkle_opt(state, STATE_BRANS, SPARKLE_STEPS_BIG);
}

// The Finalize function adds the key to the capacity part of the state.

void Finalize(uint32_t *state, const uint8_t *key)
{
  uint32_t buffer[TAG_WORDS];
  int i;

  // to prevent (potentially) unaligned memory accesses
  memcpy(buffer, key, KEY_BYTES);
  // add key to the capacity-part of the state
  for (i = 0; i < KEY_WORDS; i++)
    state[RATE_WORDS + i] ^= buffer[i];
}

// The GenerateTag function generates an authentication tag.

void GenerateTag(uint32_t *state, uint8_t *tag)
{
  memcpy(tag, (state + RATE_WORDS), TAG_BYTES);
}

// The VerifyTag function checks whether the given authentication tag is valid.
// It performs a simple constant-time comparison and returns 0 if the provided
// tag matches the computed tag and -1 otherwise.

int VerifyTag(uint32_t *state, const uint8_t *tag)
{
  uint32_t buffer[TAG_WORDS], diff = 0;
  int i;

  // to prevent (potentially) unaligned memory accesses
  memcpy(buffer, tag, TAG_BYTES);
  // constant-time comparison: 0 if equal, -1 otherwise
  for (i = 0; i < TAG_WORDS; i++)
    diff |= (state[RATE_WORDS + i] ^ buffer[i]);

  return (((int)(diff == 0)) - 1);
}

///////////////////////////////////////////////////////////////////////////////
////////////// HIGH-LEVEL AEAD FUNCTIONS (FOR USE WITH SUPERCOP) //////////////
///////////////////////////////////////////////////////////////////////////////

// High-level encryption function from SUPERCOP.
// nsec is kept for compatibility with SUPERCOP, but is not used.

int crypto_aead_encrypt(UChar *c, ULLInt *clen, const UChar *m, ULLInt mlen,
                        const UChar *ad, ULLInt adlen, const UChar *nsec, const UChar *npub,
                        const UChar *k)
{
  uint32_t state[STATE_WORDS];
  size_t msize = (size_t)mlen;
  size_t adsize = (size_t)adlen;

  Initialize(state, k, npub);
  if (adsize)
    ProcessText(state, NULL, ad, adsize, 1, 0);
  if (msize)
    ProcessText(state, c, m, msize, 0, 0);
  Finalize(state, k);
  GenerateTag(state, (c + msize));
  *clen = msize;
  *clen += TAG_BYTES;

  return 0;
}

// High-level decryption function from SUPERCOP.
// nsec is kept for compatibility with SUPERCOP, but is not used.

int crypto_aead_decrypt(UChar *m, ULLInt *mlen, UChar *nsec, const UChar *c,
                        ULLInt clen, const UChar *ad, ULLInt adlen, const UChar *npub,
                        const UChar *k)
{
  uint32_t state[STATE_WORDS];
  size_t csize = (size_t)(clen - TAG_BYTES);
  size_t adsize = (size_t)adlen;
  int retval;

  Initialize(state, k, npub);
  if (adsize)
    ProcessText(state, NULL, ad, adsize, 1, 0);
  if (csize)
    ProcessText(state, m, c, csize, 0, 1);
  Finalize(state, k);
  retval = VerifyTag(state, (c + csize));
  *mlen = csize;

  return retval;
}
