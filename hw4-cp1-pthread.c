#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef NUM_THREADS
#define NUM_THREADS 4
#endif

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
  long base_line;
  LineResult *results; // Write results here
} ThreadArg;

// Loops through a line, finds the highest ASCII value
static void *compute_max(void *arg) {
  ThreadArg *a = (ThreadArg *)arg;

  for (int i = a->start; i < a->end; i++) {
    int maxASCII = 0;

    // Find maximum ASCII value in this line
    for (int j = 0; a->lines[i][j] != '\0' && a->lines[i][j] != '\n'; j++) {
      unsigned char c = (unsigned char)a->lines[i][j];
      if (c > maxASCII) {
        maxASCII = c;
      }
    }

    a->results[i].line_number = a->base_line + i;
    a->results[i].max_val = maxASCII;
  }

  pthread_exit(NULL);
}

int main(int argc, char *argv[]) {
  char **lines = NULL;
  LineResult *results;
  long line_count = 0;
  long capacity = 1000;
  int i, rc;
  pthread_t threads[NUM_THREADS];
  pthread_attr_t attr;
  int fd;

  const char *filepath = "/homes/eyv/cis520/wiki_dump.txt";
  fd = open(filepath, O_RDONLY);

  if (fd == -1) {
    printf("Error: Could not open file %s\n", filepath);
    exit(1);
  }

  // Allocate initial space for lines
  lines = (char **)malloc(capacity * sizeof(char *));
  if (lines == NULL) {
    printf("Error: malloc failed\n");
    exit(1);
  }

  // Read file into memory using open/read
  char buffer[1024 * 1024];
  char line_buffer[MAX_LINE];
  int line_buffer_pos = 0;
  ssize_t bytes_read;

  while ((bytes_read = read(fd, buffer, sizeof(buffer))) > 0) {
    for (ssize_t j = 0; j < bytes_read; j++) {
      if (buffer[j] == '\n') {
        // End of line - process it
        line_buffer[line_buffer_pos] = '\0';

        if (line_count >= capacity) {
          capacity *= 2;
          lines = (char **)realloc(lines, capacity * sizeof(char *));
          if (lines == NULL) {
            printf("Error: realloc failed\n");
            exit(1);
          }
        }
        lines[line_count] = (char *)malloc(line_buffer_pos + 1);
        if (lines[line_count] == NULL) {
          printf("Error: malloc failed for line\n");
          exit(1);
        }
        strcpy(lines[line_count], line_buffer);
        line_count++;
        line_buffer_pos = 0;
      } else {
        if (line_buffer_pos < MAX_LINE - 1) {
          line_buffer[line_buffer_pos++] = buffer[j];
        }
      }
    }
  }

  close(fd);

  results = (LineResult *)malloc(line_count * sizeof(LineResult));
  if (results == NULL) {
    printf("Error: malloc failed for results\n");
    exit(1);
  }

  // Initialize and set thread detached attribute
  pthread_attr_init(&attr);
  pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_JOINABLE);

  // Create threads
  int lines_per_thread = (line_count + NUM_THREADS - 1) / NUM_THREADS;
  for (i = 0; i < NUM_THREADS; i++) {
    ThreadArg *arg = (ThreadArg *)malloc(sizeof(ThreadArg));
    arg->thread_id = i;
    arg->start = i * lines_per_thread;
    arg->end = (i + 1) * lines_per_thread;
    if (arg->end > line_count) {
      arg->end = line_count;
    }
    arg->lines = lines;
    arg->base_line = 0;
    arg->results = results;

    rc = pthread_create(&threads[i], &attr, compute_max, (void *)arg);
    if (rc) {
      printf("ERROR; return code from pthread_create() is %d\n", rc);
      exit(-1);
    }
  }

  // Free attribute and wait for threads
  pthread_attr_destroy(&attr);
  for (i = 0; i < NUM_THREADS; i++) {
    void *status;
    rc = pthread_join(threads[i], &status);
    if (rc) {
      printf("ERROR; return code from pthread_join() is %d\n", rc);
      exit(-1);
    }
  }

  // Print results in order
  for (i = 0; i < line_count; i++) {
    printf("%ld: %d\n", results[i].line_number, results[i].max_val);
  }

  // Cleanup
  for (i = 0; i < line_count; i++) {
    free(lines[i]);
  }
  free(lines);
  free(results);

  printf("Main: program completed. Exiting.\n");
  return 0;
}
