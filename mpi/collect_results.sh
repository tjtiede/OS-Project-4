#!/bin/bash
# collect_results.sh
# Run this after all Slurm jobs have finished to merge per-job result files
# into a single results.csv.
#
# Usage:
#   bash mpi/collect_results.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$(cd "$SCRIPT_DIR/../results" && pwd)"
OUTPUT="$RESULTS_DIR/results.csv"

# Count how many per-job files exist
shopt -s nullglob
FILES=("$RESULTS_DIR"/result_*.csv)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No result_*.csv files found in $RESULTS_DIR — have the jobs finished?"
  exit 1
fi

# Write header then append all per-job lines
echo "Version,Nodes,Cores/Node,Total Tasks,Mem/Core,Elapsed,Max RSS (KB),Exit Code" > "$OUTPUT"
cat "${FILES[@]}" >> "$OUTPUT"

echo "Collected ${#FILES[@]} results into $OUTPUT"
