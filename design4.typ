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
1. The start of the batch is always the start of a string. Besides the $0^"th"$ worker, all workers start at the beginning of their section but only compute `max_char` for lines after the first newline in their section (where the thread before them is responsible for that "leakage"). We require $1$. so that the $0^"th"$ thread always has a place to start. Note that last thread has to stop early if the last string continue into the next batch. In this case, to maintain $1.$ the main thread has to move those residual characters to the front of the buffer before filling it back up to make the next batch.

2. Each section needs to contain at least one newline. We rely on a newline in the threads partition to determine where its responsibility starts and another newline in the next partition to determine where its responsibility ends. In order to guarantee 2. we must have that
$
  #`bytes_per_thread` <= #`batch_size`
$
which is true if and only if
$
  #`max_line_length` dot #`num_workers` <= #`batch_size`
$
which we therefore have to maintain.
