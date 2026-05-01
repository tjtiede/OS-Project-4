#!/bin/bash
#SBATCH --job-name=pthread_maxchar
#SBATCH --constraint=moles
#SBATCH --time=02:00:00
#SBATCH --output=/homes/tjtiede/HW_4_Test/results/pthread_%j.out
#SBATCH --error=/homes/tjtiede/HW_4_Test/results/pthread_%j.err

NODES=$1
CORES=$2
MEM=$3

VERSION="pthread"

OUTFILE="/results/output_pthread_${SLURM_JOB_ID}.txt"
TIMEFILE="/results/time_pthread_${SLURM_JOB_ID}.txt"

/usr/bin/time -v \
    "/pthreads/bin/pthread_maxchar_${CORES}" \
    "$NODES" "$CORES" "$MEM" \
    > "$OUTFILE" 2> "$TIMEFILE"

EXIT_CODE=$?

ELAPSED=$(grep "Elapsed (wall clock)" "$TIMEFILE" | awk '{print $NF}')
MAX_RSS=$(grep "Maximum resident set size" "$TIMEFILE" | awk '{print $NF}')

RESULTS_CSV="results/results.csv"
flock "$RESULTS_CSV" bash -c \
    "echo '$VERSION,$NODES,$CORES,$MEM,$ELAPSED,$MAX_RSS,$EXIT_CODE' >> '$RESULTS_CSV'"