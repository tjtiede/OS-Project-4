#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef NUM_THREADS
#define NUM_THREADS 4
#endif

// QUESTION what is BATCH_SIZE supposed to be used for?
#define BATCH_SIZE 4096
#define MAX_LINE 8192

typedef struct {
  long line_number;
  int max_val; // max ASCII value on the line
} LineResult;

typedef struct {
  int thread_id;
  int start;
  int end;
  char **lines;
  LineResult *results; // Write results here
} ThreadArg;

// Loops through a line, finds the highest ASCII value
static void *compute_max(void *arg) {
  ThreadArg *a = (ThreadArg *)arg;

  for (int line_index = a->start; line_index < a->end; line_index += 1) {
    int maxASCII = 0;

    // Find maximum ASCII value in this line
    for (int char_index = 0; a->lines[line_index][char_index] != '\0' &&
                             a->lines[line_index][char_index] != '\n';
         char_index += 1) {
      unsigned char c = (unsigned char)a->lines[line_index][char_index];
      if (c > maxASCII) {
        maxASCII = c;
      }
    }

    a->results[line_index].line_number = line_index;
    a->results[line_index].max_val = maxASCII;
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

  // Allocate initial space for lines
  long lines_capacity = 1000;
  char **lines = (char **)malloc(lines_capacity * sizeof(char *));
  if (NULL == lines) {
    printf("Error: malloc failed\n");
    exit(1);
  }

  // Read file into memory using open/read
  // QUESTION In our testing should we try different buffer sizes?
  const int buffer_size = 1024 * 1024;
  // QUESTION What if we read the file into memory all at once and then we
  // assigned different parts of the same buffer to each thread? Say for
  // instance, with the exception of the start=0 thread, each thread could read
  // until a newline and then be responsible from that newline up to some fixed
  // end={index n}, where upon reaching that end it has to continue until a
  // newline or EOF.
  char buffer[buffer_size];
  ssize_t bytes_read;
  char line_buffer[MAX_LINE];
  int line_buffer_pos = 0;
  long line_count = 0;

  while ((bytes_read = read(fd, buffer, sizeof(buffer))) > 0) {
    for (ssize_t char_index = 0; char_index < bytes_read; char_index += 1) {
      if (buffer[char_index] == '\n') {
        // End of line - process it

        // Null terminate the line we just reached to end of
        line_buffer[line_buffer_pos] = '\0';

        if (line_count >= lines_capacity) {
          // If this next line exceeds the capacity of char** lines,
          // then realloc(lines, ...) to double its capacity
          lines_capacity *= 2;
          lines = (char **)realloc(lines, lines_capacity * sizeof(char *));
          if (NULL == lines) {
            printf("Error: realloc failed\n");
            exit(1);
          }
        }

        // Note: In malloc(...) here we add 1 to account for the null terminator
        lines[line_count] = (char *)malloc(line_buffer_pos + 1);
        if (NULL == lines[line_count]) {
          printf("Error: malloc failed for line\n");
          exit(1);
        }

        strcpy(lines[line_count], line_buffer);
        line_count += 1;
        line_buffer_pos = 0;
      } else if (line_buffer_pos < MAX_LINE - 1) {
        // If the next char is not a newline and
        // we have not exceeded the length of line_buffer[MAX_LINE]
        // then write this character into line_buffer and increment
        // line_buffer_pos
        line_buffer[line_buffer_pos] = buffer[char_index];
        line_buffer_pos += 1;
      }
    }
  }

  close(fd);

  LineResult *results = (LineResult *)malloc(line_count * sizeof(LineResult));
  if (NULL == results) {
    printf("Error: malloc failed for results\n");
    exit(1);
  }

  // Initialize and set thread detached attribute
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_JOINABLE);

  // Create threads
  pthread_t threads[NUM_THREADS];
  int pthread_create_error_number;
  // Note: adding NUM_THREADS - 1 to the numerator
  // causes the integer division to round up.
  // Therefore when line_count is not divisible by NUM_THREADS
  // the (NUM_THREADS - 1)'th thread will only be assigned
  // (lines_count % lines_per_thread) lines.
  int lines_per_thread = (line_count + NUM_THREADS - 1) / NUM_THREADS;

  for (int thread_index = 0; thread_index < NUM_THREADS; thread_index += 1) {
    ThreadArg *arg = (ThreadArg *)malloc(sizeof(ThreadArg));
    arg->thread_id = thread_index;
    arg->start = thread_index * lines_per_thread;
    arg->end = (thread_index + 1) * lines_per_thread;
    // Note: As mentioned above, here is where we handle the case of the
    // (NUM_THREADS - 1)'th thread which can receive fewer lines.
    // That is, we cap the end of this threads assigned lines at the end of the
    // char **lines buffer.
    if (arg->end > line_count) {
      arg->end = line_count;
    }
    arg->lines = lines;
    arg->results = results;

    pthread_create_error_number =
        pthread_create(&threads[thread_index], &attr, compute_max, (void *)arg);
    if (0 != pthread_create_error_number) {
      printf("ERROR; return code from pthread_create() is %d\n",
             pthread_create_error_number);
      exit(-1);
    }
  }

  // Free attribute
  pthread_attr_destroy(&attr);

  // Join threads
  for (int thread_index = 0; thread_index < NUM_THREADS; thread_index += 1) {
    void *status;
    pthread_create_error_number = pthread_join(threads[thread_index], &status);
    if (pthread_create_error_number) {
      printf("ERROR; error number from pthread_join() is %d\n",
             pthread_create_error_number);
      exit(-1);
    }
  }

  // Print results in order
  for (int line_index = 0; line_index < line_count; line_index += 1) {
    printf("%ld: %d\n", results[line_index].line_number,
           results[line_index].max_val);
    // Free line
    free(lines[line_index]);
  }

  // Cleanup
  free(lines);
  free(results);

  printf("Main: program completed. Exiting.\n");
  return 0;
}
