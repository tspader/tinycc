ROOT  := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))..
SPN   := $(ROOT)/.spn
STORE := $(SPN)/store
BUILD := $(SPN)/build

CC       ?= gcc
CFLAGS   ?= -O2
TCCFLAGS  = -I$(ROOT)

.DELETE_ON_ERROR:

# ---- sources ----

RT_LIB     = libtcc1.c stdatomic.c builtin.c
RT_ASM     = alloca.S alloca-bt.S atomic.S
RT_WIN     = crt1.c crt1w.c wincrt1.c wincrt1w.c dllcrt1.c dllmain.c
RT_WIN_ASM = chkstk.S
RT_LINUX   = dsohandle.c
RT_EXTRA   = runmain.c run_nostdlib.c bt-exe.c bt-log.c bcheck.c
RT_EXTRA_WIN = runmain.c bt-exe.c bt-log.c bt-dll.c bcheck.c

# ---- triples ----

LINUX_TRIPLE = x86_64-linux-gnu
MINGW_TRIPLE = x86_64-w64-mingw32

MINGW_CC = x86_64-w64-mingw32-gcc
MINGW_AR = x86_64-w64-mingw32-ar

COSMO_CC = $(ROOT)/toolchain/bin/x86_64-unknown-cosmo-cc
COSMO_AR = $(ROOT)/toolchain/bin/x86_64-unknown-cosmo-ar

# ---- phony ----

.PHONY: all clean linux mingw cosmo
.PHONY: linux-static linux-shared mingw-static mingw-shared

all: linux mingw
linux: linux-static linux-shared
mingw: mingw-static mingw-shared

# ---- config.h ----
# Written to TCC source root (TCC's #include "config.h" expects it there).
# CONFIG_LDDIR is Linux-specific: on Arch, /usr/lib/libc.so is a GNU ld
# linker script; CONFIG_LDDIR="lib64" makes TCC find the real .so.6 directly.
# Windows builds generate their own config.h via build-msvc.ps1 (no LDDIR).

$(ROOT)/config.h:
	@printf '%s\n' \
		'#define TCC_VERSION "0.9.28rc"' \
		'#define CONFIG_LDDIR "lib64"' \
		> $@

# ============================================================
#  Helper: build TCC runtime
#
#  Usage: $(call build_runtime,<tcc>,<outdir>,<bflag>,<platform>)
#    tcc      = path to tcc binary
#    outdir   = output directory (gets lib/ subdirectory)
#    bflag    = -B path for tcc
#    platform = linux or win32
#
#  Optional: set RT_ENV before calling for LD_LIBRARY_PATH etc.
# ============================================================

define build_runtime
	@mkdir -p $(2)/lib
	@for f in $(RT_LIB) $(RT_ASM); do \
		$(RT_ENV) $(1) -B$(3) -I$(ROOT) -I$(ROOT)/include \
			-c $(ROOT)/lib/$$f -o $(2)/lib/$${f%.*}.o || exit 1; \
	done
	$(if $(filter linux,$(4)),\
		@for f in $(RT_LINUX); do \
			$(RT_ENV) $(1) -B$(3) -I$(ROOT) -I$(ROOT)/include \
				-c $(ROOT)/lib/$$f -o $(2)/lib/$${f%.*}.o || exit 1; \
		done)
	$(if $(filter win32,$(4)),\
		@for f in $(RT_WIN); do \
			$(RT_ENV) $(1) -B$(3) -I$(ROOT) -I$(ROOT)/include \
				-c $(ROOT)/win32/lib/$$f -o $(2)/lib/$${f%.*}.o || exit 1; \
		done
		@$(RT_ENV) $(1) -B$(3) -I$(ROOT) -I$(ROOT)/include \
			-c $(ROOT)/win32/lib/$(RT_WIN_ASM) -o $(2)/lib/chkstk.o)
	$(RT_ENV) $(1) -ar $(2)/lib/libtcc1.a $(2)/lib/*.o
	@for f in $(if $(filter win32,$(4)),$(RT_EXTRA_WIN),$(RT_EXTRA)); do \
		$(RT_ENV) $(1) -B$(3) -I$(ROOT) -I$(ROOT)/include \
			-c $(ROOT)/lib/$$f -o $(2)/lib/$${f%.*}.o || exit 1; \
	done
endef

# ============================================================
#  Linux static
# ============================================================

LS_BUILD := $(BUILD)/linux-static
LS_STORE := $(STORE)/$(LINUX_TRIPLE)/static

linux-static: $(LS_STORE)/bin/hello

$(LS_BUILD)/libtcc.a: $(ROOT)/config.h
	@mkdir -p $(LS_BUILD)
	$(CC) $(CFLAGS) $(TCCFLAGS) -DONE_SOURCE=1 \
		-c $(ROOT)/libtcc.c -o $(LS_BUILD)/libtcc.o
	ar rcs $@ $(LS_BUILD)/libtcc.o

$(LS_BUILD)/tcc: $(LS_BUILD)/libtcc.a
	$(CC) $(CFLAGS) $(TCCFLAGS) -DONE_SOURCE=0 \
		$(ROOT)/tcc.c -o $@ -L$(LS_BUILD) -ltcc -lm -ldl -lpthread

$(LS_BUILD)/runtime.stamp: $(LS_BUILD)/tcc
	$(call build_runtime,$(LS_BUILD)/tcc,$(LS_BUILD)/rt,$(ROOT),linux)
	@touch $@

$(LS_STORE)/bin/hello: $(LS_BUILD)/libtcc.a $(LS_BUILD)/runtime.stamp
	@mkdir -p $(LS_STORE)/bin $(LS_STORE)/lib/tcc/include $(LS_STORE)/include
	cp $(LS_BUILD)/libtcc.a $(LS_STORE)/lib/
	cp $(ROOT)/libtcc.h $(LS_STORE)/include/
	cp $(LS_BUILD)/rt/lib/libtcc1.a $(LS_STORE)/lib/tcc/
	cp $(LS_BUILD)/rt/lib/*.o $(LS_STORE)/lib/tcc/ 2>/dev/null || true
	cp -r $(ROOT)/include/. $(LS_STORE)/lib/tcc/include/
	$(CC) $(CFLAGS) -I$(LS_STORE)/include $(SPN)/hello.c \
		-L$(LS_STORE)/lib -ltcc -lm -ldl -lpthread -o $@
	@echo "--- testing linux-static ---"
	$@ $(LS_STORE)/lib/tcc

# ============================================================
#  Linux shared
# ============================================================

LD_BUILD := $(BUILD)/linux-shared
LD_STORE := $(STORE)/$(LINUX_TRIPLE)/shared

linux-shared: $(LD_STORE)/bin/hello

$(LD_BUILD)/libtcc.so: $(ROOT)/config.h
	@mkdir -p $(LD_BUILD)
	$(CC) $(CFLAGS) $(TCCFLAGS) -DONE_SOURCE=1 -fPIC -shared \
		$(ROOT)/libtcc.c -o $@ -lm -ldl -lpthread

$(LD_BUILD)/tcc: $(LD_BUILD)/libtcc.so
	$(CC) $(CFLAGS) $(TCCFLAGS) -DONE_SOURCE=0 \
		$(ROOT)/tcc.c -o $@ -L$(LD_BUILD) -ltcc \
		-Wl,-rpath,'$$ORIGIN' -lm -ldl -lpthread

$(LD_BUILD)/runtime.stamp: $(LD_BUILD)/tcc
	$(eval RT_ENV := LD_LIBRARY_PATH=$(LD_BUILD))
	$(call build_runtime,$(LD_BUILD)/tcc,$(LD_BUILD)/rt,$(ROOT),linux)
	$(eval RT_ENV :=)
	@touch $@

$(LD_STORE)/bin/hello: $(LD_BUILD)/libtcc.so $(LD_BUILD)/runtime.stamp
	@mkdir -p $(LD_STORE)/bin $(LD_STORE)/lib/tcc/include $(LD_STORE)/include
	cp $(LD_BUILD)/libtcc.so $(LD_STORE)/lib/
	cp $(ROOT)/libtcc.h $(LD_STORE)/include/
	cp $(LD_BUILD)/rt/lib/libtcc1.a $(LD_STORE)/lib/tcc/
	cp $(LD_BUILD)/rt/lib/*.o $(LD_STORE)/lib/tcc/ 2>/dev/null || true
	cp -r $(ROOT)/include/. $(LD_STORE)/lib/tcc/include/
	$(CC) $(CFLAGS) -I$(LD_STORE)/include $(SPN)/hello.c \
		-L$(LD_STORE)/lib -ltcc -Wl,-rpath,'$$ORIGIN/../lib' \
		-lm -ldl -lpthread -o $@
	@echo "--- testing linux-shared ---"
	$@ $(LD_STORE)/lib/tcc

# ============================================================
#  MinGW cross — static
#  Cross-tcc runs on Linux, targets PE. Used to build runtime.
#  Actual libtcc.a is built with mingw cross-compiler.
# ============================================================

MX_BUILD := $(BUILD)/mingw-cross
MS_BUILD := $(BUILD)/mingw-static
MS_STORE := $(STORE)/$(MINGW_TRIPLE)/static

mingw-static: $(MS_STORE)/bin/hello.exe

$(MX_BUILD)/cross-tcc: $(ROOT)/config.h
	@mkdir -p $(MX_BUILD)
	$(CC) $(CFLAGS) $(TCCFLAGS) -DONE_SOURCE=1 -DCONFIG_TCC_STATIC=1 \
		-DTCC_TARGET_PE -DTCC_TARGET_X86_64 \
		-c $(ROOT)/libtcc.c -o $(MX_BUILD)/libtcc.o
	ar rcs $(MX_BUILD)/libtcc.a $(MX_BUILD)/libtcc.o
	$(CC) $(CFLAGS) $(TCCFLAGS) -DONE_SOURCE=0 \
		-DTCC_TARGET_PE -DTCC_TARGET_X86_64 \
		$(ROOT)/tcc.c -o $@ -L$(MX_BUILD) -ltcc -lm -ldl -lpthread

$(MX_BUILD)/runtime.stamp: $(MX_BUILD)/cross-tcc
	$(call build_runtime,$(MX_BUILD)/cross-tcc,$(MX_BUILD)/rt,$(ROOT)/win32,win32)
	@touch $@

$(MS_BUILD)/libtcc.a: $(ROOT)/config.h
	@mkdir -p $(MS_BUILD)
	$(MINGW_CC) $(CFLAGS) $(TCCFLAGS) -DONE_SOURCE=1 -DCONFIG_TCC_STATIC=1 \
		-DTCC_TARGET_PE -DTCC_TARGET_X86_64 \
		-c $(ROOT)/libtcc.c -o $(MS_BUILD)/libtcc.o
	$(MINGW_AR) rcs $@ $(MS_BUILD)/libtcc.o

$(MS_STORE)/bin/hello.exe: $(MS_BUILD)/libtcc.a $(MX_BUILD)/runtime.stamp
	@mkdir -p $(MS_STORE)/bin $(MS_STORE)/lib/tcc/lib $(MS_STORE)/lib/tcc/include $(MS_STORE)/include
	cp $(MS_BUILD)/libtcc.a $(MS_STORE)/lib/
	cp $(ROOT)/libtcc.h $(MS_STORE)/include/
	cp $(MX_BUILD)/rt/lib/* $(MS_STORE)/lib/tcc/lib/
	cp $(ROOT)/win32/lib/*.def $(MS_STORE)/lib/tcc/lib/
	cp -r $(ROOT)/include/. $(MS_STORE)/lib/tcc/include/
	cp -r $(ROOT)/win32/include/. $(MS_STORE)/lib/tcc/include/
	$(MINGW_CC) $(CFLAGS) -I$(MS_STORE)/include $(SPN)/hello.c \
		-L$(MS_STORE)/lib -ltcc -lshlwapi -static -o $@
	@echo "--- built mingw-static (run hello.exe on windows to test) ---"

# ============================================================
#  MinGW cross — shared
# ============================================================

MD_BUILD := $(BUILD)/mingw-shared
MD_STORE := $(STORE)/$(MINGW_TRIPLE)/shared

mingw-shared: $(MD_STORE)/bin/hello.exe

$(MD_BUILD)/libtcc.dll: $(ROOT)/config.h
	@mkdir -p $(MD_BUILD)
	$(MINGW_CC) $(CFLAGS) $(TCCFLAGS) -DONE_SOURCE=1 -DLIBTCC_AS_DLL \
		-DTCC_TARGET_PE -DTCC_TARGET_X86_64 \
		-shared $(ROOT)/libtcc.c -o $@ \
		-Wl,--out-implib,$(MD_BUILD)/libtcc.dll.a

$(MD_STORE)/bin/hello.exe: $(MD_BUILD)/libtcc.dll $(MX_BUILD)/runtime.stamp
	@mkdir -p $(MD_STORE)/bin $(MD_STORE)/lib/tcc/lib $(MD_STORE)/lib/tcc/include $(MD_STORE)/include
	cp $(MD_BUILD)/libtcc.dll $(MD_STORE)/bin/
	cp $(MD_BUILD)/libtcc.dll.a $(MD_STORE)/lib/
	cp $(ROOT)/libtcc.h $(MD_STORE)/include/
	cp $(MX_BUILD)/rt/lib/* $(MD_STORE)/lib/tcc/lib/
	cp $(ROOT)/win32/lib/*.def $(MD_STORE)/lib/tcc/lib/
	cp -r $(ROOT)/include/. $(MD_STORE)/lib/tcc/include/
	cp -r $(ROOT)/win32/include/. $(MD_STORE)/lib/tcc/include/
	$(MINGW_CC) $(CFLAGS) -I$(MD_STORE)/include $(SPN)/hello.c \
		-L$(MD_BUILD) -ltcc -o $@
	@echo "--- built mingw-shared (run hello.exe on windows to test) ---"

# ============================================================
#  Cosmopolitan (APE) — static
#  Builds TCC as an Actually Portable Executable using cosmo libc.
#  The resulting TCC still targets regular Linux x86_64.
# ============================================================

CS_BUILD := $(BUILD)/cosmo-static
CS_STORE := $(STORE)/x86_64-linux-ape

cosmo: $(CS_STORE)/bin/hello.com

$(CS_BUILD)/libtcc.a: $(ROOT)/config.h
	@mkdir -p $(CS_BUILD)
	$(COSMO_CC) $(CFLAGS) $(TCCFLAGS) -DONE_SOURCE=1 \
		-c $(ROOT)/libtcc.c -o $(CS_BUILD)/libtcc.o
	$(COSMO_AR) rcs $@ $(CS_BUILD)/libtcc.o

$(CS_BUILD)/tcc.com: $(CS_BUILD)/libtcc.a
	$(COSMO_CC) $(CFLAGS) $(TCCFLAGS) -DONE_SOURCE=0 \
		$(ROOT)/tcc.c -o $@ -L$(CS_BUILD) -ltcc -lm -ldl -lpthread

$(CS_BUILD)/runtime.stamp: $(CS_BUILD)/tcc.com
	$(call build_runtime,$(CS_BUILD)/tcc.com,$(CS_BUILD)/rt,$(ROOT),linux)
	@touch $@

$(CS_STORE)/bin/hello.com: $(CS_BUILD)/libtcc.a $(CS_BUILD)/runtime.stamp
	@mkdir -p $(CS_STORE)/bin $(CS_STORE)/lib/tcc/include $(CS_STORE)/include
	cp $(CS_BUILD)/libtcc.a $(CS_STORE)/lib/
	cp $(ROOT)/libtcc.h $(CS_STORE)/include/
	cp $(CS_BUILD)/rt/lib/libtcc1.a $(CS_STORE)/lib/tcc/
	cp $(CS_BUILD)/rt/lib/*.o $(CS_STORE)/lib/tcc/ 2>/dev/null || true
	cp -r $(ROOT)/include/. $(CS_STORE)/lib/tcc/include/
	$(COSMO_CC) $(CFLAGS) -I$(CS_STORE)/include $(SPN)/hello.c \
		-L$(CS_STORE)/lib -ltcc -lm -ldl -lpthread -o $@
	@echo "--- testing cosmo-static ---"
	$@ $(CS_STORE)/lib/tcc

# ============================================================
#  MSVC — run build-msvc.ps1 on piotr
# ============================================================

msvc:
	@echo "Run build-msvc.ps1 on piotr for MSVC static+shared builds"

# ============================================================
#  clean
# ============================================================

clean:
	rm -rf $(BUILD) $(ROOT)/config.h $(ROOT)/config.mak
	rm -rf $(STORE)
