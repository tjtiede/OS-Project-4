#!/bin/sh
# Usage: ./run.sh {NUM_THREADS}
make -s NUM_THREADS=$1 && ./3way-pthread-$1
