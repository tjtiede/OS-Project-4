#!/bin/bash
# submit_tests.sh
# Most of this is Claud Sonnet 4.6, I was trying to get a prototype working quickly for this .sh file, Comments are from me learning what the code does.
# Submit MPI pt2 test jobs for all parameter combinations.
# Run from the project root: bash mpi/submit_tests.sh
#
# Usage:
#   bash mpi/submit_tests.sh            # submit all combinations
#   bash mpi/submit_tests.sh --dry-run  # print sbatch commands without submitting

set -uo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "[dry-run] No jobs will be submitted."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Make sure binary is gtg
if [[ ! -f "$PROJECT_DIR/bin/pt2" ]]; then
  echo "Binary not found. Building..."
  make -C "$PROJECT_DIR" mpi
fi

# Create results dir to put all of our results into
mkdir -p "$PROJECT_DIR/results"

# ── Parameter space ──────────────────────────────────────────────────────────
CORES_LIST=(1 2 4 8 16 32)
NODES_LIST=(1 2 4 8)
# Memory values as understood by Slurm (M = MiB, G = GiB) -> This seems to work so far to the best of my testing.
MEM_LIST=("64M" "128M" "512M" "1G" "1536M" "3G")
# ─────────────────────────────────────────────────────────────────────────────

# Skip jobs that exceed beocat mole nodes
MAX_CORES_PER_NODE=40

submitted=0
skipped=0

for nodes in "${NODES_LIST[@]}"; do
  for cores in "${CORES_LIST[@]}"; do

    # skip job if the max cores go over the limit
    if (( cores > MAX_CORES_PER_NODE )); then
      echo "[skip] nodes=$nodes cores=$cores  (exceeds $MAX_CORES_PER_NODE cores/node)"
      (( skipped++ )) || true
      continue
    fi

    for mem in "${MEM_LIST[@]}"; do

      JOB_NAME="mpi_n${nodes}_c${cores}_m${mem}"

      #creates a passable arg list to Slurm to get it to work
      SBATCH_ARGS=(
        --job-name="$JOB_NAME"
        --nodes="$nodes"
        --ntasks-per-node="$cores"
        --mem-per-cpu="$mem"
        --constraint=moles
        --time=02:00:00
        --output="$PROJECT_DIR/results/${JOB_NAME}_%j.out" #output file
        --error="$PROJECT_DIR/results/${JOB_NAME}_%j.err" #error output file
        "$SCRIPT_DIR/slurm_job.sh"
        "$nodes" "$cores" "$mem"
      )

      if $DRY_RUN; then #just for testing, if its a dry run then just echo what should have been passed as if it were actually passing in information
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
