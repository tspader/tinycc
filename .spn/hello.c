#include <stdio.h>
#include <stdlib.h>
#include "libtcc.h"

static const char *prog =
    "#include <stdio.h>\n"
    "int main() {\n"
    "    printf(\"hello from JIT\\n\");\n"
    "    return 0;\n"
    "}\n";

static void error_func(void *opaque, const char *msg) {
    (void)opaque;
    fprintf(stderr, "tcc: %s\n", msg);
}

int main(int argc, char **argv) {
    const char *lib_path = NULL;
    if (argc > 1)
        lib_path = argv[1];

    TCCState *s = tcc_new();
    if (!s) {
        fprintf(stderr, "tcc_new failed\n");
        return 1;
    }

    tcc_set_error_func(s, NULL, error_func);

    if (lib_path)
        tcc_set_lib_path(s, lib_path);

    tcc_set_output_type(s, TCC_OUTPUT_MEMORY);

    if (tcc_compile_string(s, prog) < 0) {
        fprintf(stderr, "compile failed\n");
        tcc_delete(s);
        return 1;
    }

    if (tcc_relocate(s) < 0) {
        fprintf(stderr, "relocate failed\n");
        tcc_delete(s);
        return 1;
    }

    int (*func)(void) = tcc_get_symbol(s, "main");
    if (!func) {
        fprintf(stderr, "symbol 'main' not found\n");
        tcc_delete(s);
        return 1;
    }

    int ret = func();
    tcc_delete(s);
    printf("JIT returned %d\n", ret);
    return ret;
}
