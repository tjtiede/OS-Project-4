#include <fcntl.h>
#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef NUM_THREADS
#define NUM_THREADS 4
#endif

#define BATCH_SIZE 32768
#define MAX_LINE 8192

typedef struct {
  char buf[BATCH_SIZE];
  int len;
  int bytes_read;
} Batch;

typedef struct {
  int *buf; // Write results here
  int capacity;
  int len;
} MaxChars;

// Appends max_char to arg->max_chars; reallocating max_chars as needed
static void append_max_char(int max_char, MaxChars *max_chars) {
  if (max_chars->len >= max_chars->capacity) {
    // If max_chars is at capacity
    // then realloc(max_chars, ...) to double its capacity
    max_chars->capacity *= 2;
    max_chars->buf =
        (int *)realloc(max_chars->buf, max_chars->capacity * sizeof(int));
    if (NULL == max_chars->buf) {
      printf("Error: realloc failed\n");
      exit(1);
    }
  }
  max_chars->buf[max_chars->len] = max_char;
  max_chars->len += 1;
}

int main(int argc, char *argv[]) {
  const char *filepath = "/homes/eyv/cis520/wiki_dump.txt";
  int fd = open(filepath, O_RDONLY);

  if (-1 == fd) {
    printf("Error: Could not open file %s\n", filepath);
    exit(1);
  }

  int mpi_init_error_code = MPI_Init(&argc, &argv);
  if (MPI_SUCCESS != mpi_init_error_code) {
    printf("Error: MPI_Init failed\n");
    MPI_Abort(MPI_COMM_WORLD, mpi_init_error_code);
  }

  int world_size;
  int rank;
  MPI_Comm_size(MPI_COMM_WORLD, &world_size);
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);

  const int num_threads = world_size - 1;
  if (num_threads < 1) {
    printf("Error: expected at least one worker thread (2+ threads)");
    MPI_Abort(MPI_COMM_WORLD, 1);
  }

  const int bytes_per_thread = (BATCH_SIZE + num_threads - 1) / num_threads;

  if (0 == rank) {
    // Initialize batch
    Batch batch;
    batch.len = 0;
    batch.bytes_read = 0;

    long long lines_processed = 0;

    // This tracks how many bytes of batch are currently filled.
    // Those filled bytes should always be at the front of batch.
    for (;;) {
      // Read into batch starting at where the currently filled bytes end.
      // Read as many bytes as we can currently fit up to the end of batch.
      batch.bytes_read =
          read(fd, batch.buf + batch.len, BATCH_SIZE - batch.len);
      if (batch.bytes_read < 0) {
        perror("Error: read(fd, ...) failed");
        MPI_Abort(MPI_COMM_WORLD, 1);
      }
      // Add those bytes we just read to track the currently filled bytes
      batch.len += batch.bytes_read;

      // To each thread, send batch.len, batch.buf, and batch.bytes_read
      for (int thread_rank = 1; thread_rank < num_threads; thread_rank += 1) {
        MPI_Send(&batch.len, 1, MPI_INT, thread_rank, 0, MPI_COMM_WORLD);
        MPI_Send(batch.buf, batch.len, MPI_CHAR, thread_rank, 1,
                 MPI_COMM_WORLD);
        MPI_Send(&batch.bytes_read, 1, MPI_INT, thread_rank, 0, MPI_COMM_WORLD);
      }

      for (int thread_rank = 1; thread_rank < NUM_THREADS; thread_rank += 1) {
        // Receive the length of char *max_chars
        int max_char_len_capacity;
        MPI_Recv(&max_char_len_capacity, 1, MPI_INT, thread_rank, 3,
                 MPI_COMM_WORLD, MPI_STATUS_IGNORE);

        if (0 < max_char_len_capacity) {
          // If the length is not zero, read max_chars
          int *max_chars = malloc(max_char_len_capacity * sizeof(int));
          if (NULL == max_chars) {
            printf("Error: malloc failed");
            MPI_Abort(MPI_COMM_WORLD, 1);
          }
          MPI_Recv(max_chars, max_char_len_capacity, MPI_UNSIGNED_CHAR,
                   thread_rank, 4, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
          // foreach line (in order), print the corresponding max_char
          for (int i = 0; i < max_char_len_capacity; i += 1) {
            printf("%lld: %d\n", lines_processed, (int)max_chars[i]);
            lines_processed += 1;
          }
          free(max_chars);
        }
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

    // Tell worker threads we're done by sending len = -1
    batch.len = -1;
    for (int thread_rank = 1; thread_rank < num_threads; thread_rank += 1) {
      MPI_Send(&batch.len, 1, MPI_INT, thread_rank, 0, MPI_COMM_WORLD);
    }
  } else {
    // Each worker is assigned a specific region of the batch for which it is
    // responsible. Each thread's responsibility begins just after the first
    // newline in their partition, and extends to the first newline in next
    // thread's partition (besides the 0'th thread, see below).

    const int initial_thread_max_chars_size = 64;

    MaxChars max_chars;
    max_chars.buf = malloc(initial_thread_max_chars_size * sizeof(char));
    if (NULL == max_chars.buf) {
      printf("Error: malloc failed");
      MPI_Abort(MPI_COMM_WORLD, 1);
    }
    max_chars.capacity = initial_thread_max_chars_size;
    max_chars.len = 0;

    for (;;) {

      int batch_len;
      MPI_Recv(&batch_len, 1, MPI_INT, 0, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
      if (batch_len < 0) {
        break;
      }

      char *batch_buf = (char *)malloc(batch_len * sizeof(char));
      if (NULL == batch_buf) {
        printf("Error: malloc failed");
        MPI_Abort(MPI_COMM_WORLD, 1);
      }
      if (0 != batch_len) {
        MPI_Recv(batch_buf, batch_len, MPI_CHAR, 0, 1, MPI_COMM_WORLD,
                 MPI_STATUS_IGNORE);
      }

      int batch_bytes_read = MPI_Recv(&batch_len, 1, MPI_INT, 0, 0,
                                      MPI_COMM_WORLD, MPI_STATUS_IGNORE);

      int char_index = bytes_per_thread * (rank - 1);
      const int begining_of_next_threads_partition =
          char_index + bytes_per_thread;
      // The rank 1 thread is responsible for the line starting at index 0.
      // All other threads need to advance to the next newline; they're lines
      // start there
      if (1 != rank) {
        for (; char_index < batch_len && batch_buf[char_index] != '\n';
             char_index += 1)
          ;
        // Add one to skip over the newline which the loop stopped at
        char_index += 1;
      }

      unsigned char max_char = 0;
      // Foreach character up to the end of batch->buf
      while (char_index < batch_len) {
        // Note that any threads given partitions beyond the end of batch->buf
        // will not have entered into this loop
        if (batch_buf[char_index] == '\n') {
          // Upon newline, we have to append max_char to max_chars
          append_max_char(max_char, &max_chars);

          // Reset max_char back to zero for the next line
          max_char = 0;

          if (char_index >= begining_of_next_threads_partition) {
            // If this newline was in the next threads partition,
            // then we're done! (unless we're at EOF, see below).
            // Note although this line ended in the next threads partition,
            // it is still this thread's responsibility (see function comment)
            break;
          }
        } else if ((unsigned char)batch_buf[char_index] > max_char) {
          // If this char is the greatest yet to be seen,
          // then set it as the current max_char
          max_char = (unsigned char)batch_buf[char_index];
        }
        char_index += 1;
      }

      if (0 == batch_bytes_read && char_index == batch_len - 1 &&
          batch_buf[char_index] != '\n') {
        // If we bytes_read is zero, then we are at EOF.
        // If we are the last thread, then we should be the only thread where
        // char_index points to the very last char.
        // If the last char is not '\n',
        // then the last line is not terminate by a '\n',
        // therefore we didn't handle in the above loop.
        // Seemingly we should still handle this and push the current max_char
        append_max_char(max_char, &max_chars);
      }
    }
  }

  MPI_Finalize();
  return 0;
}
