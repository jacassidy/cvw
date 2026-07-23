# tests/cache/Makefile — build the processor-level cache exercise ELF.
XLEN       ?= 32
ARCH       ?= rv$(XLEN)i_zicsr
ABI        ?= $(if $(findstring 64,$(XLEN)),lp64,ilp32)
TOOLPREFIX ?= riscv64-unknown-elf-
GCC        ?= $(TOOLPREFIX)gcc
LINKER     ?= $(CURDIR)/link.ld
WORK_DIR   ?= $(CURDIR)/work

CFLAGS  := -march=$(ARCH) -mabi=$(ABI) -O0 -g -ffreestanding -nostdlib
LDFLAGS := -march=$(ARCH) -mabi=$(ABI) -nostdlib -Wl,--gc-sections -T $(LINKER)

SRC := $(CURDIR)/cache_test.S

.PHONY: all
all: $(WORK_DIR)/cache_test.elf

$(WORK_DIR)/cache_test.elf: $(SRC) $(LINKER) Makefile
	@mkdir -p $(WORK_DIR)
	$(GCC) $(CFLAGS) $(SRC) $(LDFLAGS) -o $@

.PHONY: clean
clean:
	rm -rf $(WORK_DIR)
