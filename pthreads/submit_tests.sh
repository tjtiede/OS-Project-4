#!/bin/bash
# pthreads/submit_tests.sh


# This was written with some help from AI

# Usage:
#   bash pthreads/submit_tests.sh            # submit all combinations
#   bash pthreads/submit_tests.sh --dry-run  # print sbatch commands without submitting

set -uo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "[dry-run] No jobs will be submitted."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create results dir to put all of our results into
mkdir -p "$PROJECT_DIR/results"

# ── Parameter space ──────────────────────────────────────────────────────────
NODES_LIST=(1 2 4 8)
CORES_LIST=(1 2 4 8 16 32)
MEM_LIST=("64M" "128M" "512M" "1G" "1536M" "3G")
# ─────────────────────────────────────────────────────────────────────────────

MAX_CORES_PER_NODE=40
MAX_MEM_MB=3072  # 3GB total limit per job (cores * mem_per_core)

# Helper to convert Slurm mem string to MB for comparison
mem_to_mb() {
  local mem=$1
  if [[ $mem == *G ]]; then
    echo $(( ${mem%G} * 1024 ))
  elif [[ $mem == *M ]]; then
    echo ${mem%M}
  fi
}

submitted=0
skipped=0

for nodes in "${NODES_LIST[@]}"; do


  for cores in "${CORES_LIST[@]}"; do

    # Skip if cores exceed the per-node limit
    if (( cores > MAX_CORES_PER_NODE )); then
      echo "[skip] nodes=$nodes cores=$cores  (exceeds $MAX_CORES_PER_NODE cores/node)"
      (( skipped++ )) || true
      continue
    fi

    # Make sure binary is gtg for this thread count
    BINARY="$SCRIPT_DIR/bin/pthread_maxchar_${cores}"
    if [[ ! -f "$BINARY" ]]; then
      echo "Binary not found for NUM_THREADS=$cores. Building..."
      if ! make -C "$SCRIPT_DIR" pthread \
           NUM_THREADS="$cores" \
           OUT="bin/pthread_maxchar_${cores}"; then
        echo "[FAILED] Could not build binary for NUM_THREADS=$cores — skipping"
        (( skipped += ${#MEM_LIST[@]} )) || true
        continue
      fi
    fi

    for mem in "${MEM_LIST[@]}"; do

      # Skip job if total memory exceeds the node limit
      MEM_MB=$(mem_to_mb "$mem")
      TOTAL_MEM_MB=$(( cores * MEM_MB ))
      if (( TOTAL_MEM_MB > MAX_MEM_MB )); then
        echo "[skip] nodes=$nodes cores=$cores mem=$mem  (total ${TOTAL_MEM_MB}MB exceeds ${MAX_MEM_MB}MB limit)"
        (( skipped++ )) || true
        continue
      fi

      JOB_NAME="pthread_n${nodes}_c${cores}_m${mem}"

      # Creates a passable arg list to Slurm to get it to work
      SBATCH_ARGS=(
        --job-name="$JOB_NAME"
        --nodes="$nodes"
        --ntasks-per-node=1          # one process; parallelism comes from threads
        --cpus-per-task="$cores"     # give the task enough CPUs for its threads
        --mem-per-cpu="$mem"
        --constraint=moles
        --time=02:00:00
        --output="$PROJECT_DIR/results/${JOB_NAME}_%j.out"   # output file
        --error="$PROJECT_DIR/results/${JOB_NAME}_%j.err"    # error output file
        "$SCRIPT_DIR/slurm_script.sh"
        "$nodes" "$cores" "$mem"
      )

      if $DRY_RUN; then # just for testing
        echo "sbatch ${SBATCH_ARGS[*]}"
      else
        if sbatch "${SBATCH_ARGS[@]}"; then
          echo "Submitted: nodes=$nodes cores=$cores mem=$mem"
          (( submitted++ )) || true
        else
          echo "[FAILED]  nodes=$nodes cores=$cores mem=$mem"
          (( skipped++ )) || true
        fi
      fi

    done
  done
done

if ! $DRY_RUN; then
  echo ""
  echo "Total submitted: $submitted  |  Skipped: $skipped"
  echo "Results will appear in: $PROJECT_DIR/results/"
  echo "Monitor with: squeue -u \$USER"
fi