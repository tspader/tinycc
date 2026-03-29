# Building TCC

## Linux (native, x86_64)

### libtcc.a (static library)
- Compile `libtcc.c` with: `-DONE_SOURCE=1 -DCONFIG_TCC_STATIC=1`
- Needs `config.h` with `TCC_VERSION`
- Target auto-detected from host (`__x86_64__` -> `TCC_TARGET_X86_64`)
- Link consumers with: `-lm -ldl -lpthread`

### libtcc.so (shared library)
- Compile `libtcc.c` with: `-DONE_SOURCE=1 -fPIC`
- Link as shared library

### tcc (binary)
- Compile `tcc.c` with: `-DONE_SOURCE=0`
- Link against libtcc.a or libtcc.so
- Link with: `-lm -ldl -lpthread`

### Runtime (libtcc1.a + extra objects)
- Built with the just-built `tcc`, not the host compiler
- `tcc -B. -c` for each source file
- libtcc1.a contents: libtcc1.o, dsohandle.o, stdatomic.o, atomic.o, builtin.o, alloca.o, alloca-bt.o
- Extra objects (installed separately, not in archive): runmain.o, run_nostdlib.o, bt-exe.o, bt-log.o, bcheck.o
- No bt-dll.o on Linux

### Install layout
- `$(tccdir)/libtcc1.a` - runtime archive
- `$(tccdir)/*.o` - extra objects alongside archive
- `$(tccdir)/include/*.h` - TCC's freestanding headers (stddef.h, stdarg.h, etc.)
- `$(libdir)/libtcc.a` or `libtcc.so` - compiler library
- `$(includedir)/libtcc.h` - compiler API header
- `$(bindir)/tcc` - compiler binary

### Via configure + make
```
./configure --enable-static --prefix=/usr/local
make
make install
```

---

## Windows (MSVC, x86_64)

### libtcc.lib (static library)
- Compile `libtcc.c` with MSVC (`cl`)
- Defines: `-DONE_SOURCE=1 -DCONFIG_TCC_STATIC=1 -DTCC_TARGET_PE -DTCC_TARGET_X86_64`
- Needs `config.h` with `TCC_VERSION`
- MSVC warnings to suppress: C4244, C4267, C4996, C4018, C4146
- No system libraries needed to link

### libtcc.dll (shared library)
- Compile `libtcc.c` with MSVC
- Defines: `-DONE_SOURCE=1 -DLIBTCC_AS_DLL -DTCC_TARGET_PE -DTCC_TARGET_X86_64`
- `LIBTCC_AS_DLL` sets `LIBTCCAPI` to `__declspec(dllexport)`
- MSVC flags: `-LD` (create DLL), `-O2 -W2 -Zi -MT -GS-`
- Consumers define `LIBTCCAPI` as `__declspec(dllimport)` when including libtcc.h

### tcc.exe (binary)
- Compile `tcc.c` with MSVC
- Defines: `-DONE_SOURCE=0 -DTCC_TARGET_PE -DTCC_TARGET_X86_64`
- Link against libtcc.dll or libtcc.lib
- Link with: `shlwapi.lib advapi32.lib shell32.lib`

### Runtime (libtcc1.a + extra objects)
- Built with the just-built `tcc.exe`, not MSVC
- `tcc -B<src>/win32 -I<src> -I<src>/include -c` for each source file
- libtcc1.a contents: libtcc1.o, crt1.o, crt1w.o, wincrt1.o, wincrt1w.o, dllcrt1.o, dllmain.o, chkstk.o, alloca.o, alloca-bt.o, stdatomic.o, atomic.o, builtin.o
- Extra objects (installed separately): bcheck.o, bt-exe.o, bt-log.o, bt-dll.o, runmain.o
- Archive with: `tcc -ar lib/libtcc1.a <objects>`

### Install layout
- Everything under `$(tccdir)`:
  - `lib/libtcc1.a` - runtime archive
  - `lib/*.o` - extra objects
  - `lib/*.def` - import libraries (kernel32.def, msvcrt.def, user32.def, gdi32.def, ws2_32.def)
  - `include/*.h` - merged: TCC freestanding headers + win32 C library headers + winapi headers
- `$(bindir)/tcc.exe` - compiler binary
- `$(bindir)/libtcc.dll` - compiler shared library (if DLL build)
- `$(libdir)/libtcc.h` - compiler API header
- `$(libdir)/libtcc.a` - import library for DLL

### Via build-tcc.bat
```
cd win32
build-tcc.bat -c cl -t 64
```

---

## MinGW cross-compile (Linux host -> Windows PE target)

### libtcc.a (static, cross)
- Compile `libtcc.c` with MinGW cross-compiler
- Defines: `-DONE_SOURCE=1 -DTCC_TARGET_PE -DTCC_TARGET_X86_64`
- Compiler: `x86_64-w64-mingw32-gcc`
- Produces a Linux-hosted binary that emits PE (Windows) executables

### tcc (cross-compiler binary)
- Named `x86_64-win32-tcc` (or `i386-win32-tcc` for 32-bit)
- Compile `tcc.c` with: `-DONE_SOURCE=0 -DTCC_TARGET_PE -DTCC_TARGET_X86_64`
- Link against cross libtcc.a
- Runs on Linux, produces Windows PE binaries

### Runtime (cross libtcc1.a)
- Named `x86_64-win32-libtcc1.a`
- Built with the cross tcc binary
- Same objects as Windows native: crt1.o, chkstk.o, dllcrt1.o, etc.
- Extra objects prefixed: `x86_64-win32-bcheck.o`, etc.

### Install layout
- Cross runtime installed to `$(tccdir)/win32/lib/`
- Cross headers installed to `$(tccdir)/win32/include/`
- Import .def files copied to `$(tccdir)/win32/lib/`

### Via configure + make
```
./configure --cross-prefix=x86_64-w64-mingw32- --cpu=x86_64 --targetos=WIN32
make
make install
```

Or build just the cross target from a native build:
```
make cross-x86_64-win32
```
