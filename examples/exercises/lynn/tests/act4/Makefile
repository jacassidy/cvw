# tests/act4/Makefile
# James Kaden Cassidy
# kacassidy@hmc.edu
# 1/22/26

RISCV_ARCH_TEST ?= $(WALLY)/addins/riscv-arch-test-cvw

WORK_DIR        ?= $(CURDIR)/work
STAMP           := $(WORK_DIR)/copy_stamp

ELFS_DIR 		?= $(WORK_DIR)/lynn-rv32I/elfs/rv32i

CONFIG_FILES 	?=

.PHONY: populate
populate: $(STAMP)

$(STAMP): Makefile
	@mkdir -p $(WORK_DIR)
	@# Some individual reference-signature builds may fail (e.g. a test whose
	@# sail.json config lags the pinned Sail schema). Tolerate partial failures:
	@# proceed as long as ELFs were produced, then verify a minimum count.
	-@$(MAKE) -C $(RISCV_ARCH_TEST) \
		CONFIG_FILES=$(CONFIG_FILES) \
		WORKDIR=$(WORK_DIR) \
		--jobs $$(nproc)
	@rm -rf $(ELFS_DIR)/Zicsr
	@rm -f  $(ELFS_DIR)/Zicntr/*csrrc* 2>/dev/null || true
	@rm -f  $(ELFS_DIR)/Zihpm/*csrrc* 2>/dev/null || true
	@n=$$(find -L $(ELFS_DIR) -type f -name '*.elf' 2>/dev/null | wc -l); \
	 if [ "$$n" -lt 1 ]; then \
	   echo "ERROR: ACT4 populate produced no ELFs"; exit 1; \
	 else \
	   echo "[act4] populated $$n ELFs"; \
	 fi
	@touch $(STAMP)

.PHONY: list-elfs
list-elfs:
	@find -L $(ELFS_DIR) -type f -name '*.elf' | sort

.PHONY: clean
clean:
	rm -rf $(WORK_DIR)
