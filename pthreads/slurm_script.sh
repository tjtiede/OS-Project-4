#!/bin/bash

#This was written with the help of AI

#SBATCH --job-name=pthread_maxchar
#SBATCH --constraint=moles
#SBATCH --time=02:00:00
#SBATCH --output=/homes/tjtiede/HW_4_Test/results/pthread_%j.out
#SBATCH --error=/homes/tjtiede/HW_4_Test/results/pthread_%j.err



# Arguments passed from submit_tests.sh
NODES=$1
CORES=$2        # cores per node
MEM=$3          # memory per core, e.g. "512M" or "1G"

VERSION="pthread"

# Your C program takes num_nodes, num_cores, memory_per_core as CLI args
# It also uses NUM_THREADS at compile time — we pass CORES as the logical match
OUTFILE="/homes/tjtiede/HW_4_Test/results/output_pthread_${SLURM_JOB_ID}.txt"
TIMEFILE="/homes/tjtiede/HW_4_Test/results/time_pthread_${SLURM_JOB_ID}.txt"

/usr/bin/time -v \
   "/homes/tjtiede/HW_4_Test/pthreads/bin/pthread_maxchar_${CORES}" "$NODES" "$CORES" "$MEM" \
    > "$OUTFILE" 2> "$TIMEFILE"

EXIT_CODE=$?

# Parse elapsed wall-clock time and max RSS from /usr/bin/time -v output
ELAPSED=$(grep "Elapsed (wall clock)" "$TIMEFILE" | awk '{print $NF}')
MAX_RSS=$(grep "Maximum resident set size" "$TIMEFILE" | awk '{print $NF}')

# Append result line to shared CSV (flock prevents garbled writes from concurrent jobs)
RESULTS_CSV="/homes/tjtiede/HW_4_Test/results/results.csv"
flock "$RESULTS_CSV" bash -c "echo '$VERSION,$NODES,$CORES,$MEM,$ELAPSED,$MAX_RSS,$EXIT_CODE' >> '$RESULTS_CSV'"