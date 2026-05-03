all: 3way-openmp.c
	gcc -Wall -Wextra -O2 -fopenmp -DNUM_THREADS=$(NUM_THREADS) -o 3way-openmp-$(NUM_THREADS) 3way-openmp.c

clean:
	rm -f 3way-openmp-*
