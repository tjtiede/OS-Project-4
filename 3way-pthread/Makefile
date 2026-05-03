all: 3way-pthread.c
	gcc -Wall -Wextra -O2 -pthread -DNUM_THREADS=$(NUM_THREADS) -o 3way-pthread-$(NUM_THREADS) 3way-pthread.c

clean:
	rm -f 3way-pthread-*
