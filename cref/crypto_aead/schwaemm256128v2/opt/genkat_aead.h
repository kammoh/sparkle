#ifndef GENKAT__H_
#define GENKAT__H_

#include <stdio.h>
#include <string.h>

#include "crypto_aead.h"
#include "api.h"

#define KAT_SUCCESS 0
#define KAT_FILE_OPEN_ERROR -1
#define KAT_DATA_ERROR -3
#define KAT_CRYPTO_FAILURE -4

#define MAX_FILE_NAME 256
#define MAX_MESSAGE_LENGTH 64
#define MAX_ASSOCIATED_DATA_LENGTH 64

typedef unsigned char UChar;
typedef unsigned long long int ULLInt;

void init_buffer(UChar *buffer, ULLInt numbytes);
void fprint_bstr(FILE *fp, const char *label, const UChar *data, ULLInt length);
int generate_test_vectors(void);

#endif