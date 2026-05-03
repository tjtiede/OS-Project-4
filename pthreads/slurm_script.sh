#!/bin/bash
# Written with some help from AI
#SBATCH --job-name=pthread_maxchar
#SBATCH --constraint=moles
#SBATCH --time=02:00:00
#SBATCH --output=results/pthread_%j.out
#SBATCH --error=results/pthread_%j.err

# Arguments passed from submit_tests.sh
NODES=$1
CORES=$2    # cores per node (= NUM_THREADS at compile time)
MEM=$3      # memory per core, e.g. "512M" or "1G"

VERSION="pthread"


OUTFILE="$SLURM_SUBMIT_DIR/../results/output_pthread_${SLURM_JOB_ID}.txt"
TIMEFILE="$SLURM_SUBMIT_DIR/../results/time_pthread_${SLURM_JOB_ID}.txt"

# Verify binary exists before running
if [[ ! -x "$SLURM_SUBMIT_DIR/bin/pthread_maxchar_${CORES}" ]]; then
    echo "ERROR: binary not found or not executable: $SLURM_SUBMIT_DIR/bin/pthread_maxchar_${CORES}" >&2
    exit 1
fi

# Use bash SECONDS as a reliable wall-clock fallback
SECONDS=0
/usr/bin/time -v \
    "$SLURM_SUBMIT_DIR/bin/pthread_maxchar_${CORES}" \
    "$NODES" "$CORES" "$MEM" > "$OUTFILE" 2> "$TIMEFILE"
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
    echo "WARNING: pthread exited with code $EXIT_CODE — timing may be invalid" >&2
fi

RESULTS_CSV="$SLURM_SUBMIT_DIR/../results/results.csv"
flock "$RESULTS_CSV" bash -c \
    "echo '$VERSION,$NODES,$CORES,$MEM,$ELAPSED,$MAX_RSS,$EXIT_CODE' >> '$RESULTS_CSV'"