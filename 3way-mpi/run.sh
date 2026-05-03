#!/bin/sh
make -s NUM_THREADS=$1 && mpirun ./3way-mpi-$1

