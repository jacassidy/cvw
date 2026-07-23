#!/usr/bin/env bash
# run_verilator.sh — run one ELF on a compiled Verilator model of the Lynn testbench.
# Lynn cache-development exercise.
#
# Usage: run_verilator.sh <sim_binary> <elf> [extra +plusargs...]
#
# Derives ENTRY_ADDR / TOHOST_ADDR from the ELF, feeds the memfile, writes a
# per-ELF <elf>.sim.log, and exits nonzero if the test failed or timed out.
set -uo pipefail

BIN=$1; ELF=$2; shift 2

READELF="${READELF:-riscv64-unknown-elf-readelf}"
MEMFILE="${ELF%.elf}.memfile"
LOG="${ELF}.sim.log"

if [[ ! -x "$BIN" ]]; then echo "ERROR: sim binary not found: $BIN" >&2; exit 2; fi
if [[ ! -f "$MEMFILE" ]]; then echo "ERROR: memfile not found: $MEMFILE" >&2; exit 2; fi

ENTRY=$("$READELF" -h "$ELF" | awk '/Entry point address:/ {print $NF}')
TOHOST=$("$READELF" --syms --wide "$ELF" | awk '$NF=="tohost" {print "0x"$2; exit}')
DMEM=$("$READELF" --syms --wide "$ELF" | awk '$NF=="dmem_base" {print "0x"$2; exit}')
[[ -z "$TOHOST" ]] && TOHOST=0
[[ -z "$DMEM" ]] && DMEM=0

echo "[RUN] ELF=$ELF ENTRY=$ENTRY TOHOST=$TOHOST" >&2

"$BIN" \
    +TESTNAME="$(basename "$ELF")" \
    +MEMFILE="$MEMFILE" \
    +ENTRY_ADDR="$ENTRY" \
    +TOHOST_ADDR="$TOHOST" \
    +DMEM_BASE_ADDR="$DMEM" \
    "$@" > "$LOG" 2>&1
rc=$?

# Pass criterion: testbench printed completion and no failure markers.
if grep -q "INFO: Test Completed!" "$LOG" \
   && ! grep -qE "Test Failed|FAILED|ERROR:" "$LOG"; then
    echo "[PASS] $(basename "$ELF")" >&2
    exit 0
else
    echo "[FAIL] $(basename "$ELF") (rc=$rc) — see $LOG" >&2
    exit 1
fi
