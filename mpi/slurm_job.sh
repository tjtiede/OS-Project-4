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

# Verify binary exists before running
if [[ ! -x "$SLURM_SUBMIT_DIR/bin/pt2" ]]; then
    echo "ERROR: binary not found or not executable: $SLURM_SUBMIT_DIR/bin/pt2" >&2
    exit 1
fi

# Use bash SECONDS as a reliable wall-clock fallback
SECONDS=0
/usr/bin/time -v mpirun -np "$TOTAL_TASKS" \
    "$SLURM_SUBMIT_DIR/bin/pt2" /homes/eyv/cis520/wiki_dump.txt > "$OUTFILE" 2> "$TIMEFILE"

EXIT_CODE=$?
WALL_SECONDS=$SECONDS

# Parse elapsed wall-clock time and max RSS from /usr/bin/time -v output
ELAPSED=$(grep "Elapsed (wall clock)" "$TIMEFILE" | awk '{print $NF}')
MAX_RSS=$(grep "Maximum resident set size" "$TIMEFILE" | awk '{print $NF}')

# Fall back to SECONDS-based timer if /usr/bin/time -v parsing failed
if [[ -z "$ELAPSED" ]]; then
    printf -v ELAPSED "%d:%02d:%02d" \
        $((WALL_SECONDS / 3600)) \
        $(( (WALL_SECONDS % 3600) / 60 )) \
        $((WALL_SECONDS % 60))
fi
[[ -z "$MAX_RSS" ]] && MAX_RSS="N/A"

# Warn loudly if the job failed
if [[ "$EXIT_CODE" -ne 0 ]]; then
    echo "WARNING: mpirun exited with code $EXIT_CODE — timing may be invalid" >&2
fi

# Write this job's result to its own file; collect_results.sh will merge them all later
echo "$VERSION,$NODES,$CORES,$TOTAL_TASKS,$MEM,$ELAPSED,$MAX_RSS,$EXIT_CODE" \
    > "$SLURM_SUBMIT_DIR/results/result_${SLURM_JOB_ID}.csv"
