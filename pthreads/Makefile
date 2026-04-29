CC        = gcc
CFLAGS = -Wall -Wextra -02 -pthread
TARGET = pthreads/pt1_bin

NUM_THREADS ?= 4

all: $(TARGET)

$(TARGET): pthreads/pt1.clean	
	$(CC) $(CFLAGS) -DNUM_THREADS=$(NUM_THREADS) -o $(TARGET) pthreads/pt1.c

clean:
	rm -f $(target)

.PHONY: all clean