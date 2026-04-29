#v(7cm)

#align(center)[
  #text(size: 40pt, weight: "bold")[CIS520] \ \
  #text(size: 60pt, weight: "bold")[Project 4] \ \ \
  #text(size: 30pt, weight: "bold")[Group 8] \ \ \
  #text(size: 15pt, stack(
    spacing: .5cm,
    [Zeke Flippo],
    [Vixi Spellman],
    [TJ Tiede],
  ))
]

#v(3cm)

#align(center, [= Problem Statement]) \

Given an ASCII encoded file, our goal is write a program that for each line of the input (in order) prints a corresponding line to the output "{line_number}: {max_char}" where max_char is the greatest byte on the line (not including the newline character).

#pagebreak()

#align(center, [= High Level Architecture]) \

Each of our three programs share the same high level architecture. Their differences are discussed in the following section. The fundamental idea is that we minimize the amount of synchronization needed by devising a stratgy that allows each thread to operate as independently as possible.

The main thread is only responsible for:
1. Reading fixed sized batches from the input file. We read the file in batches so that we can still make progress with arbitrarily large inputs while requiring only a fixed amount of memory.
2. Making the current batch available to the worker threads
3. Receiving the worker's results and printing them in order while keeping track of how many lines have been processed
4. Maintenance of invariant 1. (see below).

We partition the batch into sections of size
$
  #`bytes_per_thread` = ceil(#`batch_size` / #`num_workers`) #h(.5cm) "where" #`'num_workers` = #`num_threads` - 1.
$
Each worker is assigned a `thread_index` and is responsible for finding `max_char` for each of the lines that _begin_ in the section starting at
$
  #`batch`\[(n dot #`bytes_per_thread`)] \
  "and is up to and including" \
  #`batch`\[min(#`batch_size`, #h(.5cm) (n + 1) dot #`bytes_per_thread`)] \
$
Each worker returns an array containing (in order) the value of `max_char` for each of the lines it is responsible for. The main thread can iterate over each thread and each `max_char` to retrieve the values in order.

For this to work we need to maintain a couple of invariants:
1. The start of the batch is always the start of a string. Besides the $0^"th"$ worker, all workers start at the beginning of their section but only compute `max_char` for lines after the first newline in their section (where the thread before them is responsible for that "leakage"). We require $1$. so that the $0^"th"$ thread always has a place to start. Note that the last thread has to stop early if the last string continues into the next batch. In this case, to maintain $1.$ the main thread has to move those residual characters to the front of the buffer before filling it back up to make the next batch.

2. Each section needs to contain at least one newline. We rely on a newline in the threads partition to determine where its responsibility starts and another newline in the next partition to determine where its responsibility ends. In order to guarantee 2. we must have that
  $
    #`bytes_per_thread` <= #`batch_size`
  $
  which is true if and only if
  $
    #`max_line_length` dot #`num_workers` <= #`batch_size`
  $
  which we therefore have to maintain.

#pagebreak()

#align(center, [= Versions Contrasted]) \

== pthreads
Under the pthreads paradigm the main() thread spawns each of worker threads which execute thread_routine(). Main passes each thread a pointer to the batch buffer and each thread returns a pointer to an array of their `max_char`'s.

== MPI
Under the MPI paradigm we can not pass message by sharing memory so we must share memory by passing messages. Which is a fancy way to say that we have to copy all of the data between threads. In this way, the biggest difference in performance should be that the MPI code has to copy the batch buffer to each thread and the array of `max_char`'s from each thread.

== OpenMP
`TODO`

#pagebreak()

#align(center, [= Testing Methodology]) \

We want to test the performance and resource usage of our code on the "mole" class of machines with different combinations of the following: \
#h(.5cm) Nodes: 1, 2, 4, 8 \
#h(.5cm) Cores: 1, 2, 4, 8, 16, 32 \
#h(.5cm) Memory per core: 64MB, 128MB, 512MB, 1GB, 1.5GB, 3GB \
We want to show how performance differs across multiple machines vs a single machine and using different memory "budgets" where
$
  #`budget` = #`nodes` dot #`ntask-per-node` dot #`mem-per-cpu`.
$

We tested the performance of each version under 3 different memory budgets where under each budget we tested 3 different cases: \
#h(.5cm) *Maximum Nodes* --- Distribute the workload across the most machines possible. This tests the overhead of inter-node communicaiton and benefit of parallelizing acrossed machines. \
#h(.5cm) *Maximum Cores Per Node* --- Concentrate all cores on as few nodes as possible, maximizing intra-node parallelism and shared memory bandwidth. \
#h(.5cm) *Maximum Memory per Core* --- Allocate the largest possible memory per core, using fewer total ranks. This tests whether memory-bound workloads benefit from reduced core density.

#table(
  columns: (auto, auto, auto, auto),
  table.cell(stroke: (left: none, top: none))[],
  [*Budget A: \~4096 MB*],
  [*Budget B: \~8192 MB*],
  [*Budget C: \~16384 MB*],
  [*Max. Nodes*],
  [4 nodes, 4 cores, 512 MB],
  [8 nodes, 2 cores, 512 MB],
  [8 nodes, 4 cores, 512 MB],

  [*Max. Cores*],
  [1 nodes, 16 cores, 256 MB],
  [1 nodes, 16 cores, 512 MB],
  [1 nodes, 32 cores, 512 MB],

  [*Max. Mem.*],
  [2 nodes, 4 cores, 512 MB],
  [2 nodes, 4 cores, 1 GB],
  [2 nodes, 4 cores, 2 GB],
)


