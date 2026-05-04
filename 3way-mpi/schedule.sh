#!/bin/sh
# ./schedule.sh {time} {mem-per-cpu} {num_nodes}
make -s NUM_THREADS=$3 && sbatch --time=$1 --mem-per-cpu=$2 --cpus-per-task=1 --ntasks=$3 --nodes=$4 --constraint=moles ./run.sh $3

