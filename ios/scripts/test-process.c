#include "../OpenCode/Runtime/ProcessBridge.h"
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

int main(void) {
    char log[] = "/tmp/opencode-process-XXXXXX";
    int fd = mkstemp(log);
    assert(fd >= 0);
    close(fd);
    char *env[] = { "PORT_TEST=passed", NULL };
    char *args[] = { "/bin/sh", "-c", "printf '%s' \"$PORT_TEST\"; printf ':stderr' >&2; exit 7", NULL };
    pid_t pid = 0;
    assert(oc_spawn(args[0], args, env, log, &pid) == 0);
    assert(pid > 0);
    assert(oc_wait(pid) == 7);
    FILE *file = fopen(log, "r");
    assert(file != NULL);
    char output[64] = {0};
    assert(fread(output, 1, sizeof(output) - 1, file) == 13);
    fclose(file);
    assert(strcmp(output, "passed:stderr") == 0);
    struct stat info;
    assert(stat(log, &info) == 0 && (info.st_mode & 0777) == 0600);
    assert(oc_spawn("/nonexistent/opencode-node", args, env, log, &pid) == ENOENT);
    char *waiting[] = { "/bin/sleep", "60", NULL };
    assert(oc_spawn(waiting[0], waiting, env, log, &pid) == 0);
    oc_stop(pid);
    assert(oc_wait(pid) == 143);
    unlink(log);
    puts("PASS: subprocess environment, output, exit code, launch failure and termination");
    return 0;
}
