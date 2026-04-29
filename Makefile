CC_MPI   = mpicc
CC_OMP   = gcc
CFLAGS   = -O2 -Wall

# Output directories
BINDIR   = bin

.PHONY: all mpi clean

all: mpi

$(BINDIR):
	mkdir -p $(BINDIR)

# MPI build
mpi: $(BINDIR)/pt2

$(BINDIR)/pt2: mpi/pt2.c | $(BINDIR)
	$(CC_MPI) $(CFLAGS) -o $@ $<

clean:
	/bin/rm -rf $(BINDIR)
