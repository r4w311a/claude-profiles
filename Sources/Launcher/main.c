#include <CoreFoundation/CoreFoundation.h>
#include <libgen.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int profileDataDir(char *buffer, size_t size) {
    CFBundleRef bundle = CFBundleGetMainBundle();
    if (!bundle) return 0;
    CFTypeRef value = CFBundleGetValueForInfoDictionaryKey(bundle, CFSTR("ClaudeProfileDataDir"));
    if (!value || CFGetTypeID(value) != CFStringGetTypeID()) return 0;
    return CFStringGetFileSystemRepresentation((CFStringRef)value, buffer, (CFIndex)size) && buffer[0];
}

static int claudeBinary(char *buffer, size_t size) {
    char path[PATH_MAX];
    uint32_t length = sizeof(path);
    char resolved[PATH_MAX];
    if (_NSGetExecutablePath(path, &length) != 0 || !realpath(path, resolved)) return 0;
    return snprintf(buffer, size, "%s/Claude", dirname(resolved)) < (int)size;
}

int main(int argc, char *argv[]) {
    char dataDir[PATH_MAX];
    char binary[PATH_MAX];
    if (!profileDataDir(dataDir, sizeof(dataDir))) {
        fprintf(stderr, "claude-profile-launcher: ClaudeProfileDataDir is missing from Info.plist\n");
        return 78;
    }
    if (!claudeBinary(binary, sizeof(binary))) {
        fprintf(stderr, "claude-profile-launcher: could not locate the Claude binary\n");
        return 78;
    }

    char flag[PATH_MAX + 32];
    snprintf(flag, sizeof(flag), "--user-data-dir=%s", dataDir);

    char **args = calloc((size_t)argc + 2, sizeof(char *));
    if (!args) return 71;
    int count = 0;
    args[count++] = binary;
    args[count++] = flag;
    for (int i = 1; i < argc; i++) args[count++] = argv[i];
    args[count] = NULL;

    execv(binary, args);
    perror("claude-profile-launcher");
    return 71;
}
