#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef NUM_THREADS
#define NUM_THREADS 4
#endif

enum {
  NUM_WORKERS = NUM_THREADS - 1,
  MAX_LINE_LENGTH = 1 << 13,
  BATCH_SIZE = MAX_LINE_LENGTH * NUM_WORKERS
};

// We ever need one copy of this data, so in main we have an instance of batch
// wihch we pass every thread a pointer to
typedef struct {
  char buf[BATCH_SIZE];
  int len;
  int bytes_read;
} Batch;

typedef struct {
  int worker_index;
  Batch *batch;
  int *max_chars; // Write results here
  int max_chars_capacity;
  int max_chars_len;
} WorkerArg;

const int bytes_per_worker = (BATCH_SIZE + NUM_WORKERS - 1) / NUM_WORKERS;

// Appends max_char to arg->max_chars; reallocating max_chars as needed
static void append_max_char(int max_char, WorkerArg *arg) {
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
// batch for which it is responsible. Each workers's responsibility begins just
// after the first newline in their partition, and extends to the first newline
// in next workers's partition (besides the 0'th worker, see below).
static void *worker_routine(void *worker_args) {
  WorkerArg *arg = (WorkerArg *)worker_args;
  Batch *batch = arg->batch;

  int char_index = bytes_per_worker * arg->worker_index;
  const int begining_of_next_workers_partition = char_index + bytes_per_worker;
  // The 0'th thread is responsible for the line starting at index 0.
  // All other threads need to advance to the next newline; they're lines start
  // there
  if (0 != arg->worker_index) {
    for (; char_index < batch->len && batch->buf[char_index] != '\n';
         char_index += 1)
      ;
    // Add one to skip over the newline which the loop stopped at
    char_index += 1;
  }

  unsigned char max_char = 0;
  // Foreach character up to the end of batch->buf
  while (char_index < batch->len) {
    // Note that any workers given partitions beyond the end of batch->buf
    // will not have entered into this loop
    if (batch->buf[char_index] == '\n') {
      // Upon newline, we have to append max_char to max_chars
      append_max_char(max_char, arg);

      // Reset max_char back to zero for the next line
      max_char = 0;

      if (char_index >= begining_of_next_workers_partition) {
        // If this newline was in the next worker's partition,
        // then we're done! (unless we're at EOF, see below).
        // Note although this line ended in the next worker's partition,
        // it is still this worker's responsibility (see function comment)
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
    // If we are the last worker, then we should be the only worker where
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

  // Create worker threads
  pthread_t workers[NUM_WORKERS];
  WorkerArg worker_args[NUM_WORKERS];
  const int initial_worker_max_chars_size = 64;
  for (int worker_index = 0; worker_index < NUM_WORKERS; worker_index += 1) {
    worker_args[worker_index].worker_index = worker_index;
    worker_args[worker_index].batch = &batch;
    worker_args[worker_index].max_chars =
        malloc(initial_worker_max_chars_size * sizeof(int));
    if (NULL == worker_args[worker_index].max_chars) {
      printf("Error: malloc failed\n");
      exit(1);
    }
    worker_args[worker_index].max_chars_capacity =
        initial_worker_max_chars_size;
    worker_args[worker_index].max_chars_len = 0;
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

    for (int worker_index = 0; worker_index < NUM_WORKERS; worker_index += 1) {
      int pthread_create_error_number =
          pthread_create(&workers[worker_index], &attr, worker_routine,
                         (void *)&worker_args[worker_index]);
      if (0 != pthread_create_error_number) {
        printf("ERROR; return code from pthread_create() is %d\n",
               pthread_create_error_number);
        exit(1);
      }
    }

    for (int worker_index = 0; worker_index < NUM_WORKERS; worker_index += 1) {
      void *status;
      int pthread_join_error_number =
          pthread_join(workers[worker_index], &status);
      if (pthread_join_error_number) {
        printf("ERROR; error number from pthread_join() is %d\n",
               pthread_join_error_number);
        exit(1);
      }
    }

    // Print results in order
    for (int worker_index = 0; worker_index < NUM_WORKERS; worker_index += 1) {
      for (int i = 0; i < worker_args[worker_index].max_chars_len; i += 1) {
        printf("%lld: %d\n", lines_processed,
               worker_args[worker_index].max_chars[i]);
        lines_processed += 1;
      }
      // Reset the len of this worker's max_chars
      worker_args[worker_index].max_chars_len = 0;
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
}
