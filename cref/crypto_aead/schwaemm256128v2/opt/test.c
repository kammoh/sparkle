#include <stdio.h>
#include <string.h>

#include "crypto_aead.h"
#include "api.h"
#include "genkat_aead.h"

int main(void)
{
  int ret;
  
  ret = generate_test_vectors();
  if (ret != KAT_SUCCESS) {
    fprintf(stderr, "test vector generation failed with code %d\n", ret);
  }
  
  return ret;
}