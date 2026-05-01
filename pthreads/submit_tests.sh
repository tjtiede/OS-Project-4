#!/bin/bash
# pthreads/submit_tests.sh
# Submit pthread test jobs for all parameter combinations.
# Run from the project root: bash pthreads/submit_tests.sh
#
# Usage:
#   bash pthreads/submit_tests.sh            # submit all combinations
#   bash pthreads/submit_tests.sh --dry-run  # print sbatch commands without submitting

set -uo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "[dry-run] No jobs will be submitted."
fi

PROJECT_DIR="$(dirname "$(realpath "$0")")/.."
SCRIPT_DIR="$PROJECT_DIR/pthreads"

mkdir -p "$PROJECT_DIR/results"
RESULTS_CSV="$PROJECT_DIR/results/results.csv"
if [[ ! -f "$RESULTS_CSV" ]]; then
  echo "Version,Nodes,Cores/Node,Mem/Core,Elapsed,Max RSS (KB),Exit Code" > "$RESULTS_CSV"
fi

# ── Parameter space ───────────────────────────────────────────────────────────
NODES=1
CORES_LIST=(1 2 4 8 16 32)
MEM_LIST=("64M" "128M" "512M" "1G" "1536M" "3G")
# ─────────────────────────────────────────────────────────────────────────────

MAX_CORES_PER_NODE=40

submitted=0
skipped=0

for cores in "${CORES_LIST[@]}"; do

  if (( cores > MAX_CORES_PER_NODE )); then
    echo "[skip] cores=$cores  (exceeds $MAX_CORES_PER_NODE cores/node)"
    (( skipped++ )) || true
    continue
  fi

  BINARY="$SCRIPT_DIR/bin/pthread_maxchar_${cores}"

  # Build if binary doesn't exist yet
  if [[ ! -f "$BINARY" ]]; then
    echo "Building binary for NUM_THREADS=$cores ..."
    if ! make -C "$SCRIPT_DIR" pthread \
         NUM_THREADS="$cores" \
         OUT="bin/pthread_maxchar_${cores}"; then
      echo "[FAILED] Could not build binary for NUM_THREADS=$cores — skipping"
      (( skipped += ${#MEM_LIST[@]} )) || true
      continue
    fi
  else
    echo "[exists] Binary for NUM_THREADS=$cores already built, skipping build."
  fi

  for mem in "${MEM_LIST[@]}"; do

    JOB_NAME="pthread_n${NODES}_c${cores}_m${mem}"

    SBATCH_ARGS=(
      --job-name="$JOB_NAME"
      --nodes="$NODES"
      --ntasks-per-node=1
      --cpus-per-task="$cores"
      --mem-per-cpu="$mem"
      --constraint=moles
      --time=02:00:00
      --output="$PROJECT_DIR/results/${JOB_NAME}_%j.out"
      --error="$PROJECT_DIR/results/${JOB_NAME}_%j.err"
      "$SCRIPT_DIR/slurm_script.sh"
      "$NODES" "$cores" "$mem"
    )

    if $DRY_RUN; then
      echo "sbatch ${SBATCH_ARGS[*]}"
    else
      if sbatch "${SBATCH_ARGS[@]}"; then
        echo "Submitted: cores=$cores mem=$mem"
        (( submitted++ )) || true
      else
        echo "[FAILED]  cores=$cores mem=$mem"
        (( skipped++ )) || true
      fi
    fi

  done
done

if ! $DRY_RUN; then
  echo ""
  echo "Total submitted: $submitted  |  Skipped: $skipped"
  echo "Results will appear in: $PROJECT_DIR/results/"
  echo "Monitor with: squeue -u \$USER"
fi