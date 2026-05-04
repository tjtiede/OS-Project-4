#!/bin/sh
# run.sh {num_threads}
mpirun -N $1 ./3way-mpi-$1

