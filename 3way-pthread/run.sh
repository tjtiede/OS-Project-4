#!/bin/sh
make -s NUM_THREADS=$1 && ./3way-pthread-$1
