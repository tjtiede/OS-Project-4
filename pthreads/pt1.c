#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h> //Added this to analyize runtime
#include <linux/time.h>


#ifndef NUM_THREADS
#define NUM_THREADS 4
#endif

#define BATCH_SIZE 32768
#define MAX_LINE 8192

// We ever need one copy of this data, so in main we have an instance of batch
// wihch we pass every thread a pointer to
typedef struct {
  char buf[BATCH_SIZE];
  int len;
  int bytes_read;
} Batch;

typedef struct {
  int thread_index;
  Batch *batch;
  int *max_chars; // Write results here
  int max_chars_capacity;
  int max_chars_len;
} ThreadArg;

const int bytes_per_thread = (BATCH_SIZE + NUM_THREADS - 1) / NUM_THREADS;

// Appends max_char to arg->max_chars; reallocating max_chars as needed
static void append_max_char(int max_char, ThreadArg *arg) {
  if (arg->max_chars_len >= arg->max_chars_capacity) {
    // If max_chars is at capacity
    // then realloc(max_chars, ...) to double its capacity
    arg->max_chars_capacity *= 2;
    arg->max_chars =
        (int *)realloc(arg->max_chars, arg->max_chars_capacity * sizeof(int));
    if (NULL == arg->max_chars) {
      printf("Error: realloc failed\n");
      exit(1);
    }
  }
  arg->max_chars[arg->max_chars_len] = max_char;
  arg->max_chars_len += 1;
}

// Each thread begins execution here and is assigned a specific region of the
// batch for which it is responsible. Each thread's responsibility begins just
// after the first newline in their partition, and extends to the first newline
// in next thread's partition (besides the 0'th thread, see below).
static void *thread_routine(void *thread_args) {
  ThreadArg *arg = (ThreadArg *)thread_args;
  Batch *batch = arg->batch;

  int char_index = bytes_per_thread * arg->thread_index;
  const int begining_of_next_threads_partition = char_index + bytes_per_thread;
  // The 0'th thread is responsible for the line starting at index 0.
  // All other threads need to advance to the next newline; they're lines start
  // there
  if (0 != arg->thread_index) {
    for (; char_index < batch->len && batch->buf[char_index] != '\n';
         char_index += 1)
      ;
    // Add one to skip over the newline which the loop stopped at
    char_index += 1;
  }

  unsigned char max_char = 0;
  // Foreach character up to the end of batch->buf
  while (char_index < batch->len) {
    // Note that any threads given partitions beyond the end of batch->buf
    // will not have entered into this loop
    if (batch->buf[char_index] == '\n') {
      // Upon newline, we have to append max_char to max_chars
      append_max_char(max_char, arg);

      // Reset max_char back to zero for the next line
      max_char = 0;

      if (char_index >= begining_of_next_threads_partition) {
        // If this newline was in the next threads partition,
        // then we're done! (unless we're at EOF, see below).
        // Note although this line ended in the next threads partition,
        // it is still this thread's responsibility (see function comment)
        break;
      }
    } else if ((unsigned char)batch->buf[char_index] > max_char) {
      // If this char is the greatest yet to be seen,
      // then set it as the current max_char
      max_char = (unsigned char)batch->buf[char_index];
    }
    char_index += 1;
  }

  if (0 == batch->bytes_read && char_index == batch->len - 1 &&
      batch->buf[char_index] != '\n') {
    // If we bytes_read is zero, then we are at EOF.
    // If we are the last thread, then we should be the only thread where
    // char_index points to the very last char.
    // If the last char is not '\n',
    // then the last line is not terminate by a '\n',
    // therefore we didn't handle in the above loop.
    // Seemingly we should still handle this and push the current max_char
    append_max_char(max_char, arg);
  }

  pthread_exit(NULL);
}

int main(int argc, char *argv[]) {
  //Added this to accept args when program is ran to show how many Nodes, cores, Memory-per-core, Total memory used, and runtime 
  //of the pthreads section.
  if(argc != 4){
    fprintf(stderr, "Usage: %s <num_nodes> <num_cores> <memory_per_core>\n", argv[0]);
    exit(1);
  }
  //Stores the test values for later use
  int num_nodes = atoi(argv[1]);
  int num_cores = atoi(argv[2]);
  double memory_per_core = atoi(argv[3]);

  //Calculates total memory used and is stored for later use
  double total_memory = num_nodes * num_cores * memory_per_core;
  //Timer used for calculating runtime
  struct timespec start, end;
  //store inital time
  clock_gettime(CLOCK_MONOTONIC, &start);

 


  const char *filepath = "/homes/eyv/cis520/wiki_dump.txt";
  int fd = open(filepath, O_RDONLY);

  if (-1 == fd) {
    printf("Error: Could not open file %s\n", filepath);
    exit(1);
  }

  // Initialize and set thread detached attribute
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_JOINABLE);

  // Initialize batch
  Batch batch;
  batch.len = 0;
  batch.bytes_read = 0;

  // Create threads
  pthread_t threads[NUM_THREADS];
  ThreadArg thread_args[NUM_THREADS];
  const int initial_thread_max_chars_size = 64;
  for (int thread_index = 0; thread_index < NUM_THREADS; thread_index += 1) {
    thread_args[thread_index].thread_index = thread_index;
    thread_args[thread_index].batch = &batch;
    thread_args[thread_index].max_chars =
        malloc(initial_thread_max_chars_size * sizeof(int));
    if (NULL == thread_args[thread_index].max_chars) {
      printf("Error: malloc failed\n");
      exit(1);
    }
    thread_args[thread_index].max_chars_capacity =
        initial_thread_max_chars_size;
    thread_args[thread_index].max_chars_len = 0;
  }

  long long lines_processed = 0;

  // This tracks how many bytes of batch are currently filled.
  // Those filled bytes should always be at the front of batch.
  for (;;) {
    // Read into batch starting at where the currently filled bytes end.
    // Read as many bytes as we can currently fit up to the end of batch.
    batch.bytes_read = read(fd, batch.buf + batch.len, BATCH_SIZE - batch.len);
    if (-1 == batch.bytes_read) {
      perror("Error: read(fd, ...) failed");
      exit(1);
    }
    // Add those bytes we just read to track the currently filled bytes
    batch.len += batch.bytes_read;

    for (int thread_index = 0; thread_index < NUM_THREADS; thread_index += 1) {
      int pthread_create_error_number =
          pthread_create(&threads[thread_index], &attr, thread_routine,
                         (void *)&thread_args[thread_index]);
      if (0 != pthread_create_error_number) {
        printf("ERROR; return code from pthread_create() is %d\n",
               pthread_create_error_number);
        exit(1);
      }
    }

    for (int thread_index = 0; thread_index < NUM_THREADS; thread_index += 1) {
      void *status;
      int pthread_join_error_number =
          pthread_join(threads[thread_index], &status);
      if (pthread_join_error_number) {
        printf("ERROR; error number from pthread_join() is %d\n",
               pthread_join_error_number);
        exit(1);
      }
    }

    // Print results in order
    for (int thread_index = 0; thread_index < NUM_THREADS; thread_index += 1) {
      for (int i = 0; i < thread_args[thread_index].max_chars_len; i += 1) {
        printf("%lld: %d\n", lines_processed,
               thread_args[thread_index].max_chars[i]);
        lines_processed += 1;
      }
      // Reset the len of this thread's max_chars
      thread_args[thread_index].max_chars_len = 0;
    }

    // If we've just handled the last batch that was left over from the last
    // read, then we're done!
    if (0 == batch.bytes_read) {
      break;
    }

    // Find the last newline in batch,
    // we haven't processed anything after that yet.
    int last_newline_index = batch.len - 1;
    for (;; last_newline_index -= 1) {
      if (batch.buf[last_newline_index] == '\n') {
        break;
      }
    }
    // If the newline is the last char in batch, we can just set batch_len = 0
    // Otherwise we have to move the unprocessed bytes to the front of the
    // buffer and update batch_len accordingly.
    int bytes_to_move = batch.len - last_newline_index - 1;
    if (last_newline_index != BATCH_SIZE - 1) {
      memmove(batch.buf, batch.buf + last_newline_index + 1, bytes_to_move);
    }
    batch.len = bytes_to_move;
  }

  close(fd);

  // Store end time
  clock_gettime(CLOCK_MONOTONIC, &end);
  //Calculate the time difference for later analysis
  double elapsed = (end.tv_sec - start.tv_sec) +
                   (end.tv_nsec - start.tv_nsec) / 1e9;

  //Print analysis results for program in a single line
  // The actual limiting should take place in the scheduler (SLURM)
   printf("ptread %d %d %.2f %.2f %.4f\n", num_nodes, num_cores, memory_per_core, total_memory, elapsed);

  

}
