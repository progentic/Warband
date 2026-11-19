#include <stdio.h>
#include <string.h>
#include "sqlite3.h"

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    const int version = sqlite3_libversion_number();
    const char *source = sqlite3_sourceid();
    printf("SQLite version number: %d\nSQLite source ID: %s\n", version, source);
    if (version != 3054001 || strcmp(source, argv[1]) != 0) {
        fputs("SQLite library identity mismatch\n", stderr);
        return 1;
    }

    const char *required[] = {"THREADSAFE=1", "OMIT_LOAD_EXTENSION", "DQS=0"};
    for (int i = 0; i < 3; ++i) {
        if (!sqlite3_compileoption_used(required[i])) {
            fprintf(stderr, "Missing compile option: %s\n", required[i]);
            return 1;
        }
    }
    const char *option;
    for (int i = 0; (option = sqlite3_compileoption_get(i)) != NULL; ++i)
        printf("compile option: %s\n", option);
    return 0;
}
