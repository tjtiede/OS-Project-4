#!/bin/sh
sbatch --time=$1 --mem-per-cpu=$2 --cpus-per-task=$3 --ntasks=$4 --nodes=$5 ./run.sh $4

