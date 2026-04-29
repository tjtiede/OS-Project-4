#!/bin/bash
# submit_tests.sh
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

# Ensure the binary is built
if [[ ! -f "$PROJECT_DIR/bin/pt2" ]]; then
  echo "Binary not found. Building..."
  make -C "$PROJECT_DIR" mpi
fi

# Create results directory and initialize shared CSV with header (if not already present)
mkdir -p "$PROJECT_DIR/results"
RESULTS_CSV="$PROJECT_DIR/results/results.csv"
if [[ ! -f "$RESULTS_CSV" ]]; then
  echo "Version,Nodes,Cores/Node,Total Tasks,Mem/Core,Elapsed,Max RSS (KB),Exit Code" > "$RESULTS_CSV"
fi

# ── Parameter space ──────────────────────────────────────────────────────────
CORES_LIST=(1 2 4 8 16 32)
NODES_LIST=(1 2 4 8)
# Memory values as understood by Slurm (M = MiB, G = GiB)
MEM_LIST=("64M" "128M" "512M" "1G" "1536M" "3G")
# ─────────────────────────────────────────────────────────────────────────────

# Beocat mole nodes have 40 cores total; skip combinations that exceed this.
MAX_CORES_PER_NODE=40

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

    for mem in "${MEM_LIST[@]}"; do

      JOB_NAME="mpi_n${nodes}_c${cores}_m${mem}"

      SBATCH_ARGS=(
        --job-name="$JOB_NAME"
        --nodes="$nodes"
        --ntasks-per-node="$cores"
        --mem-per-cpu="$mem"
        --constraint=moles
        --time=02:00:00
        --output="$PROJECT_DIR/results/${JOB_NAME}_%j.out"
        --error="$PROJECT_DIR/results/${JOB_NAME}_%j.err"
        "$SCRIPT_DIR/slurm_job.sh"
        "$nodes" "$cores" "$mem"
      )

      if $DRY_RUN; then
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
