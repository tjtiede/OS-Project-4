#!/bin/bash
# Written by AI for now just to see if I can get the output format somewhat correct
#SBATCH --job-name=mpi_pt2
#SBATCH --constraint=moles
#SBATCH --time=02:00:00
#SBATCH --output=results/mpi_%j.out
#SBATCH --error=results/mpi_%j.err

# Arguments passed from submit_tests.sh
NODES=$1
CORES=$2       # cores per node (= ntasks-per-node)
MEM=$3         # memory per core, e.g. "512M" or "1G"
VERSION="MPI pt2"

TOTAL_TASKS=$(( NODES * CORES ))

# Capture max RSS via /usr/bin/time -v; redirect program output to per-job file
OUTFILE="$SLURM_SUBMIT_DIR/results/output_mpi_${SLURM_JOB_ID}.txt"
TIMEFILE="$SLURM_SUBMIT_DIR/results/time_mpi_${SLURM_JOB_ID}.txt"

/usr/bin/time -v mpirun -np "$TOTAL_TASKS" \
    "$SLURM_SUBMIT_DIR/bin/pt2" /homes/eyv/cis520/wiki_dump.txt > "$OUTFILE" 2> "$TIMEFILE"

EXIT_CODE=$?

# Parse elapsed wall-clock time and max RSS from /usr/bin/time -v output
ELAPSED=$(grep "Elapsed (wall clock)" "$TIMEFILE" | awk '{print $NF}')
MAX_RSS=$(grep "Maximum resident set size" "$TIMEFILE" | awk '{print $NF}')

# Append result line to shared CSV (flock prevents garbled output from concurrent jobs)
RESULTS_CSV="$SLURM_SUBMIT_DIR/results/results.csv"
flock "$RESULTS_CSV" bash -c "echo '$VERSION,$NODES,$CORES,$TOTAL_TASKS,$MEM,$ELAPSED,$MAX_RSS,$EXIT_CODE' >> '$RESULTS_CSV'"
