# synth/Makefile — free local synthesis (sv2v + Yosys + ABC + Sky130).
# Lynn cache-development exercise.
#
# Legacy Design Compiler flow is preserved behind SYNTH_TOOL=dc.

SYNTH_TOOL     ?= yosys
CORE_VARIANT   ?= cache
XLEN           ?= 32

LYNN           := $(CURDIR)/..
PROCESSOR_SRC  ?= $(LYNN)/external/RISC-V-Pipelined-Processor/src
WRAPPER_DIR    ?= $(LYNN)/rtl
INC_DIR        ?= $(LYNN)/external/RISC-V-Pipelined-Processor/incdir
WORK_DIR       ?= $(CURDIR)/work

ifeq ($(CORE_VARIANT),baseline)
  SYNTH_TOP    ?= testingCore
else
  SYNTH_TOP    ?= testingCacheCore
endif

# Free Sky130 Liberty (overridable). Falls back to the vendored copy.
LIBERTY_FILE   ?= $(LYNN)/external/lib/sky130_fd_sc_hd__tt_025C_1v80.lib

# Make the vendored free tools visible to the flow.
EXT_TOOLS      := $(LYNN)/external/tools
export PATH := $(EXT_TOOLS)/oss-cad-suite/bin:$(EXT_TOOLS)/sv2v-Linux:$(PATH)

.PHONY: all synth clean
all: synth

ifeq ($(SYNTH_TOOL),dc)
# ---- Legacy Design Compiler flow (optional, requires Synopsys DC) ----
synth:
	@mkdir -p $(WORK_DIR)
	@$(MAKE) -C $(WALLY)/synthDC \
		OUTPUTBASEDIR=$(WORK_DIR) NAME=lynn DESIGN=$(SYNTH_TOP) \
		PROCESSORTOP=$(SYNTH_TOP) INCDIR=$(INC_DIR) HDLDIR=$(PROCESSOR_SRC) \
		LYNN=1 TECH=sky130 CONFIG=- MOD=- SYNTH_FILES= LIB_FILES= synth
else
# ---- Default free Yosys flow ----
synth:
	@CORE_VARIANT=$(CORE_VARIANT) PROCESSOR_SRC=$(PROCESSOR_SRC) \
	 WRAPPER_DIR=$(WRAPPER_DIR) INC_DIR=$(INC_DIR) SYNTH_TOP=$(SYNTH_TOP) \
	 XLEN=$(XLEN) LIBERTY_FILE=$(LIBERTY_FILE) WORK_DIR=$(WORK_DIR) \
	 $(CURDIR)/run_yosys.sh
endif

clean:
	rm -rf $(WORK_DIR)
