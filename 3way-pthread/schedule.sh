#!/bin/sh
# Usage: ./schedule.sh {time} {mem-per-cpu} {num_cores}
sbatch --time=$1 --mem-per-cpu=$2 --cpus-per-task=$3 --ntasks=1 --nodes=1 --constraint=moles ./run.sh $3
