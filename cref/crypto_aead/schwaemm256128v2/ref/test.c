#include <stddef.h> // for size_t
#include <stdio.h>
#include <string.h> // for memcpy, memset
#include "schwaemm_cfg.h"
#include "sparkle_ref.h"
#include "crypto_aead.h"
#include "api.h"
#include "genkat_aead.h"

typedef unsigned char UChar;
typedef unsigned long long int ULLInt;
#define TAG_BYTES (SCHWAEMM_TAG_LEN / 8)
#define STATE_BRANS (SPARKLE_STATE / 64)
#define RATE_BRANS (SPARKLE_RATE / 64)
#define RATE_WORDS (SPARKLE_RATE / 32)
#define RATE_BYTES  (SPARKLE_RATE/8)


// int main(void)
// {
//   int ret;
  
//   ret = generate_test_vectors();
//   if (ret != KAT_SUCCESS) {
//     fprintf(stderr, "test vector generation failed with code %d\n", ret);
//   }
  
//   return ret;
// }

void Initialize(SparkleState *state, const uint8_t *key, const uint8_t *nonce);

void test_sparkle(int brans, int steps)
{
    SparkleState state = {{0}, {0}};

    printf("input:\n");
    print_state_ref(&state, brans);
    sparkle_ref(&state, brans, steps);
    printf("sparkle:\n");
    print_state_ref(&state, brans);
    sparkle_inv_ref(&state, brans, steps);
    printf("sparkle inv:\n");

    printf("\n");
}

int crypto_aead_test(UChar *c, ULLInt *clen, const UChar *m, ULLInt mlen,
                     const UChar *ad, ULLInt adlen, const UChar *nsec, const UChar *npub,
                     const UChar *k)
{
    SparkleState state;
    // size_t msize = (size_t)mlen;
    // size_t adsize = (size_t)adlen;
    uint32_t outbuf[RATE_WORDS];

    Initialize(&state, k, npub);
    print_state_ref(&state, STATE_BRANS);
    printf("\n");

    for (int i = 0; i < RATE_BRANS; i++)
    {
        outbuf[2 * i] = state.x[i];
        outbuf[2 * i + 1] = state.y[i];
    }

    *clen = RATE_BYTES;

    memcpy(c, outbuf, RATE_BYTES);

    return 0;
}
