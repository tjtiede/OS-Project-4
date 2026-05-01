CC         = gcc
CFLAGS     = -Wall -Wextra -O2 -pthread
BINDIR     = bin
NUM_THREADS ?= 4
OUT ?= $(BINDIR)/pthread_maxchar_$(NUM_THREADS)

.PHONY: all pthread clean

all: pthread

$(BINDIR):
	mkdir -p $(BINDIR)

pthread: $(BINDIR)
	$(CC) $(CFLAGS) -DNUM_THREADS=$(NUM_THREADS) -o $(OUT) pt1.c

clean:
	rm -f $(BINDIR)/pthread_maxchar_*