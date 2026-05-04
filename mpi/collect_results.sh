#!/bin/bash
# collect_results.sh
# All this does is combine all of the results files into one results.csv file
# To use this just enter: bash mpi/collect_results.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" #absolute path
RESULTS_DIR="$(cd "$SCRIPT_DIR/../results" && pwd)"
OUTPUT="$RESULTS_DIR/results.csv" #the output file

# how many job file dumps exist for the result_*.csv files
shopt -s nullglob
FILES=("$RESULTS_DIR"/result_*.csv)

if [[ ${#FILES[@]} -eq 0 ]]; then #if no result files exist then print an error
  echo "No result files found."
  exit 1
fi

# Write the header for better readability then append all lines together to avoid a race condition. Vixi's idea
echo "Version,Nodes,Cores/Node,Total Tasks,Mem/Core,Elapsed,Max RSS (KB),Exit Code" > "$OUTPUT"
cat "${FILES[@]}" >> "$OUTPUT"

echo "Collected ${#FILES[@]} results into $OUTPUT"
