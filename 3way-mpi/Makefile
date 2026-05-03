all: 3way-mpi.c
	mpicc -Wall -Wextra -O2 -DNUM_THREADS=$(NUM_THREADS) -o 3way-mpi-$(NUM_THREADS) 3way-mpi.c

clean:
	rm -f 3way-mpi-*

