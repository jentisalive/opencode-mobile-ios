#include <sys/types.h>
int oc_spawn(const char *executable, char *const argv[], char *const env[], const char *log, pid_t *pid);
int oc_wait(pid_t pid);
void oc_stop(pid_t pid);
void oc_force_stop(pid_t pid);
