
SOURCES = $(wildcard *.c)
HEADERS = $(wildcard *.h)
OBJECTS = $(SOURCES:.c=.o)

%%.o: %%.c $(HEADERS)
	$(CC) $(CFLAGS) -c $< -o $@

genkat_aead: $(OBJECTS) $(HEADERS)
	$(CC) $(CFLAGS) -o $@ $(OBJECTS) $(HEADERS)
	
clean:
	rm -f *.o

test: genkat_aead
	./genkat_aead
	diff LWC_AEAD_KAT_128_256.txt ../ref/LWC_AEAD_KAT_128_256.txt