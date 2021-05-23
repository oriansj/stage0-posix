TARGETS = hex0 hex1 hex2 kaem-minimal

all: $(TARGETS)

clean:
	rm $(TARGETS)

.PHONY: all clean

%: %.c ../M2libc/bootstrappable.c
	$(CC) $^ -o $@
