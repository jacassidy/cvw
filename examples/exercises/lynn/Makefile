# Lynn cache-development exercise — free local flow (Verilator + Yosys)
# James Kaden Cassidy 1/1/2026 kacassidy@hmc.edu
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Default flow uses only free, local tools:
#   simulation : Verilator
#   synthesis  : sv2v + Yosys + ABC + Sky130 (open) Liberty
# No Questa/ModelSim/Design Compiler required. See README.md.

# ============================================================
#                    Top-level configuration
# ============================================================

# verilator (default) | questa (legacy)
SIM            ?= verilator
# cache (TestingCacheCore) | baseline (TestingCore)
CORE_VARIANT   ?= cache
XLEN           ?= 32
ARCH           ?= rv$(XLEN)i_zicsr
# 1 = emit FST waveform
TRACE          ?= 0
# yosys (default) | dc (legacy Design Compiler)
SYNTH_TOOL     ?= yosys
GUI            ?= 0
SAIL           ?= 0

# ---- External processor checkout (reproducible) ----
CORE_REPO      ?= https://github.com/jacassidy/RISC-V-Pipelined-Processor.git
CORE_REF       ?= 52d2dd9edc2441ab000bd30bc0bbff5fc247f560
CORE_DIR       ?= $(CURDIR)/external/RISC-V-Pipelined-Processor
CORE_PATCH     ?= $(CURDIR)/patches/0001-external-membackpressure.patch

# ============================================================
#              Variant-dependent processor selection
# ============================================================

WRAPPER_DIR    := $(CURDIR)/rtl
PROCESSOR_SRC  := $(CORE_DIR)/src
INC_DIR        ?= $(CORE_DIR)/incdir

ifeq ($(CORE_VARIANT),baseline)
  PROCESSOR_TOP    := testingCore
  VARIANT_SOURCES  := $(sort $(shell find $(PROCESSOR_SRC) -type f -name '*.sv' 2>/dev/null))
else ifeq ($(CORE_VARIANT),cache)
  PROCESSOR_TOP    := testingCacheCore
  VARIANT_SOURCES  := $(sort $(shell find $(PROCESSOR_SRC) -type f -name '*.sv' 2>/dev/null)) \
                      $(WRAPPER_DIR)/SimpleDataCache.sv $(WRAPPER_DIR)/TestingCacheCore.sv
else
  $(error CORE_VARIANT must be 'baseline' or 'cache' (got '$(CORE_VARIANT)'))
endif

PROCESSOR_CONFIG ?= $(CURDIR)/sample_processor/config

# ============================================================
#                       Repo paths
# ============================================================

COREMARK_DIR     := $(CURDIR)/coremark
C_TEST_DIR       := $(CURDIR)/tests/C
ACT4_TEST_DIR    := $(CURDIR)/tests/act4
BRINGUP_TEST_DIR := $(CURDIR)/tests/bringup
CACHE_TEST_DIR   := $(CURDIR)/tests/cache
TESTBENCH_DIR    := $(CURDIR)/tb
SYNTH_DIR        := $(CURDIR)/synth
RESULTS_DIR      := $(CURDIR)/results
BIN_DIR          := $(CURDIR)/bin
EXT_TOOLS        := $(CURDIR)/external/tools

WORK_DIR         := $(CURDIR)/work
RISCV_ARCH_TEST  ?= $(WALLY)/addins/riscv-arch-test-cvw
LINKER           ?= $(PROCESSOR_CONFIG)/link.ld

# Per-variant Verilator build directory so baseline and cache never collide.
VBUILD_DIR       := $(WORK_DIR)/verilator/$(CORE_VARIANT)
VSIM_BIN         := $(VBUILD_DIR)/obj_dir/Vtb
VSTAMP           := $(VBUILD_DIR)/.built

TB_FILES         := $(TESTBENCH_DIR)/testbench.sv $(TESTBENCH_DIR)/ram1p1rwb.sv
SV_PACKAGES      := $(sort $(shell find $(PROCESSOR_SRC) -type f -name '*.pkg' 2>/dev/null))

# ============================================================
#                          Tools
# ============================================================

# Prefer the full CORE-V Wally RISC-V toolchain ($RISCV/bin, GCC >= 15 with
# newlib) over any minimal system cross-compiler, so CoreMark's libc headers
# (string.h, etc.) are available and ACT4's GCC-version check passes.
ifneq ($(RISCV),)
export PATH := $(RISCV)/bin:$(PATH)
endif

PYTHON     := python3
TOOLPREFIX := riscv64-unknown-elf-
READELF    := $(TOOLPREFIX)readelf
OBJDUMP    := $(TOOLPREFIX)objdump
SIZE       := $(TOOLPREFIX)size
ELF2HEX    := elf2hex
VERILATOR  ?= verilator
ABI        := $(if $(findstring 64,$(XLEN)),lp64,ilp32)

# Use the CORE-V Wally elf2hex (uv script, takes <elf> <memfile>). Reference it
# explicitly: $RISCV/bin may contain an incompatible SiFive elf2hex with a
# different CLI, and it now sits earlier on PATH.
ELF2HEX_CMD := $(WALLY)/bin/elf2hex

# Verilator flags. CASEX / width warnings in the student RTL are benign; we lint
# them separately. TIMESCALEMOD is suppressed because the TB sets the timescale.
VFLAGS := --binary --timing -j 0 \
    --top-module testbench \
    --timescale 1ns/1ps \
    -Wno-TIMESCALEMOD -Wno-WIDTH -Wno-CASEX -Wno-UNUSEDSIGNAL \
    -Wno-VARHIDDEN -Wno-DECLFILENAME -Wno-CASEINCOMPLETE -Wno-fatal
VDEFS  := +define+PROCESSOR_TOP=$(PROCESSOR_TOP) +define+XLEN$(XLEN)
ifeq ($(TRACE),1)
  VFLAGS += --trace-fst
  VDEFS  += +define+TRACE
endif

ELFS ?=

.PHONY: all
all: build

# ============================================================
#                    doctor / fetch-core
# ============================================================

.PHONY: doctor
doctor:
	@$(PYTHON) $(BIN_DIR)/doctor.py

.PHONY: fetch-core
fetch-core:
	@CORE_REPO="$(CORE_REPO)" CORE_REF="$(CORE_REF)" CORE_DIR="$(CORE_DIR)" \
	 CORE_PATCH="$(CORE_PATCH)" $(BIN_DIR)/fetch_core.sh

.PHONY: fetch-tools
fetch-tools:
	@$(BIN_DIR)/fetch_tools.sh

# Ensure the checkout exists before anything that needs the RTL.
$(PROCESSOR_SRC):
	@$(MAKE) fetch-core

# ============================================================
#                    Lint / Build (Verilator)
# ============================================================

.PHONY: lint
lint: | $(PROCESSOR_SRC)
	@echo "[LINT] $(CORE_VARIANT) ($(PROCESSOR_TOP)) with Verilator"
	@$(VERILATOR) --lint-only --quiet \
		--top-module $(PROCESSOR_TOP) \
		$(VDEFS) \
		-I$(INC_DIR) -I$(WRAPPER_DIR) \
		$(SV_PACKAGES) $(VARIANT_SOURCES) $(TB_FILES) \
		-Wall -Wno-UNUSEDSIGNAL -Wno-VARHIDDEN -Wno-TIMESCALEMOD \
		-Wno-CASEX -Wno-WIDTH -Wno-DECLFILENAME -Wno-CASEINCOMPLETE \
		&& echo "[LINT] OK"

.PHONY: build
build: $(VSTAMP)

$(VSTAMP): $(SV_PACKAGES) $(VARIANT_SOURCES) $(TB_FILES) Makefile | $(PROCESSOR_SRC)
	@echo "[BUILD] $(CORE_VARIANT) ($(PROCESSOR_TOP)) -> $(VBUILD_DIR)"
	@mkdir -p $(VBUILD_DIR)
	@$(VERILATOR) $(VFLAGS) $(VDEFS) \
		-I$(INC_DIR) -I$(WRAPPER_DIR) \
		--Mdir $(VBUILD_DIR)/obj_dir -o Vtb \
		$(SV_PACKAGES) $(VARIANT_SOURCES) $(TB_FILES)
	@touch $@

# ============================================================
#                Generic memfile / run flow
# ============================================================

.PRECIOUS: %.memfile
%.memfile: %.elf
	@echo "[MEM] $@"
	@$(ELF2HEX_CMD) $< $@

# Run a set of ELFs:  make run ELFS="a.elf b.elf"
.PHONY: run
run: build
	@set -e; for elf in $(ELFS); do \
		$(MAKE) --no-print-directory $${elf%.elf}.memfile; \
		$(BIN_DIR)/run_verilator.sh $(VSIM_BIN) $$elf; \
	done

# SAIL reference-model run is preserved (make run SAIL=1 ELFS=...)
ifeq ($(SAIL),1)
run: run-sail
.PHONY: run-sail
run-sail:
	@for elf in $(ELFS); do \
		sail_riscv_sim $$elf --config $(PROCESSOR_CONFIG)/sail.json \
			--trace-all --trace-output $$elf.sail.trace > $$elf.sail.log 2>&1; \
	done
endif

# ============================================================
#                          Tests
# ============================================================

.PHONY: bringup_test
bringup_test: build
	@$(MAKE) -C $(BRINGUP_TEST_DIR) XLEN=$(XLEN) ARCH="$(ARCH)" ABI=$(ABI) TOOLPREFIX=$(TOOLPREFIX)
	@$(MAKE) --no-print-directory run ELFS="$(BRINGUP_TEST_DIR)/work/bringup.elf"

.PHONY: C_test
C_test: build
	@$(MAKE) -C $(C_TEST_DIR) XLEN=$(XLEN) ARCH="$(ARCH)" ABI=$(ABI) \
		LINKER=$(LINKER) TOOLPREFIX=$(TOOLPREFIX) $(C_TEST_DIR)/work/c_test.elf
	@$(MAKE) --no-print-directory run ELFS="$(C_TEST_DIR)/work/c_test.elf"

# Processor-level cache exercise test (loads/stores/conflicts/byte/half).
.PHONY: cache-test
cache-test: build
	@$(MAKE) -C $(CACHE_TEST_DIR) XLEN=$(XLEN) ARCH="$(ARCH)" ABI=$(ABI) \
		LINKER=$(CACHE_TEST_DIR)/link.ld TOOLPREFIX=$(TOOLPREFIX)
	@$(MAKE) --no-print-directory run ELFS="$(CACHE_TEST_DIR)/work/cache_test.elf"

# Standalone RTL cache unit test (its own tiny testbench, no processor).
.PHONY: cache-unit-test
cache-unit-test: | $(PROCESSOR_SRC)
	@$(BIN_DIR)/run_cache_unit_test.sh

# ACT4 generation needs: mise (ruby/uv for the UDB testgen), GCC >= 15 from
# $RISCV/bin, and a Sail reference model (vendored under external/tools).
# ACT4's framework requires the Sail model version string to be exactly "0.10".
SAIL_BIN := $(EXT_TOOLS)/sail010/sail-riscv-Linux-x86_64/bin
ACT4_PATH := $(HOME)/.local/bin:$(RISCV)/bin:$(SAIL_BIN):$(PATH)

.PHONY: act4
act4:
	@PATH="$(ACT4_PATH)" MISE_YES=1 $(MAKE) -C $(ACT4_TEST_DIR) \
		RISCV_ARCH_TEST=$(RISCV_ARCH_TEST) \
		CONFIG_FILES=$(PROCESSOR_CONFIG)/test_config.yaml populate

.PHONY: test
test: build | act4
	@echo "[ACT4] running architecture suite ($(CORE_VARIANT))"
	@for elf in $$( $(MAKE) -s -C $(ACT4_TEST_DIR) list-elfs ); do \
		$(MAKE) --no-print-directory $${elf%.elf}.memfile >/dev/null 2>&1; \
		$(BIN_DIR)/run_verilator.sh $(VSIM_BIN) $$elf >/dev/null 2>&1 || true; \
	done
	@cd $(ACT4_TEST_DIR) && $(PYTHON) $(BIN_DIR)/scan_test_logs.py --sail $(SAIL)

.PHONY: coremark
coremark: build
	@$(MAKE) -C $(COREMARK_DIR) XLEN=$(XLEN) ARCH="$(ARCH)" ABI=$(ABI) \
		LINKER=$(LINKER) TOOLPREFIX=$(TOOLPREFIX)
	@$(MAKE) --no-print-directory run ELFS="$(COREMARK_DIR)/work/coremark.bare.riscv.elf"

# ============================================================
#                        Synthesis
# ============================================================

.PHONY: synth
synth: | $(PROCESSOR_SRC)
	@$(MAKE) -C $(SYNTH_DIR) \
		SYNTH_TOOL=$(SYNTH_TOOL) CORE_VARIANT=$(CORE_VARIANT) \
		PROCESSOR_SRC=$(PROCESSOR_SRC) WRAPPER_DIR=$(WRAPPER_DIR) \
		INC_DIR=$(INC_DIR) SYNTH_TOP=$(PROCESSOR_TOP) XLEN=$(XLEN)

# ============================================================
#                   Benchmark / Report
# ============================================================

.PHONY: benchmark
benchmark:
	@$(BIN_DIR)/benchmark.sh

.PHONY: report
report:
	@$(PYTHON) $(BIN_DIR)/report.py

.PHONY: score
score:
	@$(PYTHON) $(BIN_DIR)/score.py $(SYNTH_DIR)/work $(COREMARK_DIR)/work \
		--output-log $(CURDIR)/score.log || true

# ============================================================
#                          Clean
# ============================================================

.PHONY: clean clean-act4 clean-coremark clean-synth clean-all

clean:
	@$(MAKE) -C $(C_TEST_DIR) clean 2>/dev/null || true
	@$(MAKE) -C $(BRINGUP_TEST_DIR) clean 2>/dev/null || true
	@$(MAKE) -C $(CACHE_TEST_DIR) clean 2>/dev/null || true
	rm -rf $(WORK_DIR)
	rm -f score.log
	find . -name '*.sim.log' -delete 2>/dev/null || true
	find . -name '*.memfile' -delete 2>/dev/null || true

clean-coremark:
	@$(MAKE) -C $(COREMARK_DIR) clean 2>/dev/null || true

clean-act4:
	@$(MAKE) -C $(ACT4_TEST_DIR) clean 2>/dev/null || true

clean-synth:
	@$(MAKE) -C $(SYNTH_DIR) clean 2>/dev/null || true

clean-all: clean clean-act4 clean-synth clean-coremark
	rm -rf $(RESULTS_DIR)
