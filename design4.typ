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
  #`bytes_per_thread` = ceil(#`batch_size` / #`num_workers`) #h(.5cm) "where" #`num_workers` = #`num_threads` - 1.
$
Each worker is assigned a `worker_index` and is responsible for finding `max_char` for each of the lines that _begin_ in the section starting at
$
  #`batch`\[(#`worker_index` dot #`bytes_per_thread`)] \
  "and is up to and including" \
  #`batch`\[min(#`batch_size`, #h(.5cm) (#`worker_index` + 1) dot #`bytes_per_thread`)] \
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
OpenMP is nearly identical to pthreads except with a different a syntax that is generally less explicit.

#pagebreak()

#align(center, [= Testing Methodology]) \

We want to test the performance and resource usage of our code on the "mole" class of machines with different combinations of the following: \
#h(.5cm) Nodes: 1, 2, 4, 8 \
#h(.5cm) Cores: 1, 2, 4, 8, 16, 32 \
#h(.5cm) Memory per core: 64MB, 128MB, 512MB, 1GB, 1.5GB, 3GB \

When using `sbatch` to schedule jobs, we control the parameters \
#h(.5cm) `time: uint`, \
#h(.5cm) `mem-per-cpu: uint` $times {"MB", "GB"}$, \
#h(.5cm) `cpus-per-task: uint`, \
#h(.5cm) `ntasks: uint`, \
#h(.5cm) `nodes: uint`, \
where the total number of cores is equal to
$
  #`cores` = #`cpus-per-task` dot #`ntasks`.
$
Therefore for a given number of `cores` we can determine the appropriate `cpus-per-task` we can divide both sides by `ntasks` yeilding
$
  #`cpus-per-task` = #`cores` / #`ntasks`
$
where (since `cpus-per-task` is an integer) we must have that `cores` is a multiple of `ntasks`. Also consider that each node only has so many cores.

*pthreads and OpenMP* are single machine only. Under these paradigms we always have that
$
  #`ntasks` = 1 #h(.5cm) "and" #h(.5cm) #`cpus-per-task` = #`num_threads`.
$

Reciprocally, under *MPI* we always have that
$
  #`ntasks` = #`num_threads` = N #h(.5cm) "and" #h(.5cm) #`cpus-per-task` = 1.
$

We want to show how performance differs across multiple machines vs a single machine and using different memory "*budgets*" where
$
  #`budget` = #`cores` dot #`mem-per-cpu`.
$

#pagebreak()

#align(center, [= Testing Methodology Cont.]) \

We tested each paradigm with test cases tailored to their execution model.

#align(center, [== pthreads and OpenMP])
These pthreads and OpenMP are limited to a single-machine execution with shared memory. We test scaling on a single node with varying thread counts and memory allocations:


#table(
  columns: (auto, auto, auto, auto),
  table.cell(stroke: (left: none, top: none))[*Configuration*],
  [*Budget A: 2 GB*],
  [*Budget B: 4 GB*],
  [*Budget C: 8 GB*],
  [*1 thread*],
  [1 node, 1 thread, 2 GB],
  [1 node, 1 thread, 4 GB],
  [1 node, 1 thread, 8 GB],
  [*4 threads*],
  [1 node, 4 threads, 512 MB],
  [1 node, 4 threads, 1 GB],
  [1 node, 4 threads, 2 GB],
  [*8 threads*],
  [1 node, 8 threads, 256 MB],
  [1 node, 8 threads, 512 MB],
  [1 node, 8 threads, 1 GB],
  [*16 threads*],
  [1 node, 16 threads, 128 MB],
  [1 node, 16 threads, 256 MB],
  [1 node, 16 threads, 512 MB],
)

#align(center, [== MPI])
MPI can distribute work across multiple processes and nodes. We test both single-node and multi-node scenarios to isolate communication overhead:

#table(
  columns: (auto, auto, auto, auto),
  table.cell(stroke: (left: none, top: none))[*Configuration*],
  [*Budget A: 2 GB*],
  [*Budget B: 4 GB*],
  [*Budget C: 8 GB*],
  [*1 node, 4 ranks*],
  [1 node, 4 ranks, 512 MB/rank],
  [1 node, 4 ranks, 1 GB/rank],
  [1 node, 4 ranks, 2 GB/rank],
  [*2 nodes, 2 ranks each*],
  [2 nodes, 2 ranks each, 512 MB/rank],
  [2 nodes, 2 ranks each, 1 GB/rank],
  [2 nodes, 2 ranks each, 2 GB/rank],
  [*4 nodes, 1 rank each*],
  [4 nodes, 1 rank each, 512 MB/rank],
  [4 nodes, 1 rank each, 1 GB/rank],
  [4 nodes, 1 rank each, 2 GB/rank],
  [*8 nodes, 1 rank each*],
  [8 nodes, 1 rank each, 256 MB/rank],
  [8 nodes, 1 rank each, 512 MB/rank],
  [8 nodes, 1 rank each, 1 GB/rank],
)

Where *Budget* represents the total memory available: $#`budget` = #`num_processes` dot #`mem-per-process`$. This allows us to observe how each paradigm scales with increasing memory resources while controlling for communication overhead (MPI single-node baseline vs. multi-node scenarios) and thread scaling efficiency (pthreads/OpenMP).

#pagebreak()

#align(center, [= Performance Analysis]) \

#image("images/Screenshot 2026-05-03 231309.png")
Raw data used to compare paradigms

#align(center, [= Performance Analysis Cont.]) \
#image("images/Screenshot 2026-05-03 231253.png")
Calculated average times and used memory of each test case
#image("images/Screenshot 2026-05-03 231237.png")
Calculated standard deviation for time and used memory

#align(center, [= Performance Analysis Cont.]) \
#image("images/Average Execution Time by Config & Program.png")
Average Execution time of each paradigm

#align(center, [= Performance Analysis Cont.]) \
#image("images/Average Memory Usage by Config & Program.png")
Average Memory Usage of each paradigm

#align(center, [= Performance Analysis Cont.]) \
#image("images/Avg Execution Time per Program (± StdDev).png")
Standard deviation of execution time

#align(center, [= Performance Analysis Cont.]) \
#image("images/Avg Memory Usage per Program (± StdDev).png")
Standard deviaton of memory usage

#align(center, [= Performance Analysis Cont.]) \
#image("images/Execution Time Scaling (Line).png")
Execution time scaling

#align(center, [= Performance Analysis Cont.]) \
#image("images/Memory Usage Scaling (Line).png")
Memory usage scaling

#pagebreak()

#align(center, [= Appendix - pthreads Controlling Scripts]) \

#align(center, [== `3way-pthread/run.sh`])
#raw(read("3way-pthread/run.sh"), lang: "sh")

#align(center, [== `3way-pthread/schedule.sh`])
#raw(read("3way-pthread/schedule.sh"), lang: "sh")

#pagebreak()

#align(center, [= Appendix - OpenMP Controlling Scripts]) \

#align(center, [== `3way-openmp/run.sh`])
#raw(read("3way-openmp/run.sh"), lang: "sh")

#align(center, [== `3way-openmp/schedule.sh`])
#raw(read("3way-openmp/schedule.sh"), lang: "sh")

#pagebreak()

#align(center, [= Appendix - MPI Controlling Scripts]) \

Steps to do MPI testing: \
Enter the following: \
#h(.5cm) `module load CMake/3.23.1-GCCcore-11.3.0 foss/2022a OpenMPI/4.1.4-GCC-11.3.0 CUDA/11.7.0` \
Then: \
#h(.5cm) `bash mpi/submit_tests.sh` \
After the tests have all run, combine the results to a results.csv file: \
#h(.5cm) `bash mpi/collect_results.sh`

#align(center, [== `3way-mpi/submit_test.sh`])
#raw(read("3way-mpi/submit_tests.sh"), lang: "sh")

#pagebreak()

#align(center, [== `3way-mpi/slurm_job.sh`])
#raw(read("3way-mpi/slurm_job.sh"), lang: "sh")

#pagebreak()

#align(center, [= Appendix - Sample Output])
#align(center, [(It wraps around into a second column)]) \
#align(center, grid(
  columns: (auto, auto),
  column-gutter: 5cm,
  ```
  0: 125
  1: 125
  2: 125
  3: 125
  4: 125
  5: 125
  6: 125
  7: 125
  8: 125
  9: 124
  10: 226
  11: 195
  12: 125
  13: 226
  14: 195
  15: 125
  16: 125
  17: 125
  18: 125
  19: 125
  20: 125
  21: 226
  22: 125
  23: 125
  24: 125
  25: 195
  26: 125
  27: 125
  28: 226
  29: 125
  30: 125
  31: 125
  32: 125
  33: 125
  34: 214
  35: 226
  36: 226
  37: 226
  38: 125
  39: 125
  40: 125
  41: 125
  42: 125
  43: 125
  44: 226
  45: 226
  46: 195
  47: 217
  48: 125
  49: 226
  ```,
  ```
  50: 226
  51: 125
  52: 195
  53: 125
  54: 125
  55: 125
  56: 226
  57: 125
  58: 125
  59: 125
  60: 125
  61: 125
  62: 125
  63: 125
  64: 226
  65: 125
  66: 125
  67: 125
  68: 226
  69: 194
  70: 194
  71: 226
  72: 125
  73: 226
  74: 197
  75: 125
  76: 226
  77: 125
  78: 224
  79: 226
  80: 209
  81: 125
  82: 195
  83: 226
  84: 125
  85: 125
  86: 226
  87: 226
  88: 125
  89: 226
  90: 226
  91: 125
  92: 206
  93: 226
  94: 195
  95: 195
  96: 125
  97: 226
  98: 226
  99: 195
  ```,
))
