#include "ProcessBridge.h"
#include <spawn.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>
#include <errno.h>

int oc_spawn(const char *executable, char *const argv[], char *const env[], const char *log, pid_t *pid) {
    posix_spawn_file_actions_t actions;
    int error = posix_spawn_file_actions_init(&actions);
    if (error) return error;
    posix_spawnattr_t attributes;
    error = posix_spawnattr_init(&attributes);
    if (error) { posix_spawn_file_actions_destroy(&actions); return error; }
    error = posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP);
    if (!error) error = posix_spawnattr_setpgroup(&attributes, 0);
    if (!error) error = posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    if (!error) error = posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, log, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (!error) error = posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO);
    if (!error) error = posix_spawn(pid, executable, &actions, &attributes, argv, env);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attributes);
    return error;
}
int oc_wait(pid_t pid) {
    int status = 0;
    while (waitpid(pid, &status, 0) < 0) { if (errno != EINTR) return -errno; }
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}
void oc_stop(pid_t pid) { if (pid > 0) kill(-pid, SIGTERM); }

void oc_force_stop(pid_t pid) { if (pid > 0) kill(-pid, SIGKILL); }
