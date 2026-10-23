# ============================================================================
# Makefile - Build C Extension, Run Unit Tests, Benchmarks & Tick Plant Stack
# ============================================================================

Q ?= q
CC ?= gcc
CFLAGS := -O3 -march=native -shared -fPIC -DKXVER=3 -Wall -Wextra

.PHONY: all native test bench start stop clean

all: native

native:
	@mkdir -p lib
	$(CC) $(CFLAGS) src/native/fast_microstructure.c -o lib/fast_microstructure.so -lm
	@echo "[OK] Built C plugin: lib/fast_microstructure.so"

test:
	$(Q) tests/test_all.q -exit

bench:
	$(Q) benchmarks/bench.q -exit

start:
	./scripts/run_stack.sh

stop:
	./scripts/stop_stack.sh

clean:
	rm -rf lib/*.so logs/* tplog/* hdb/* pids/*
