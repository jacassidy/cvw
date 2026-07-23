#!/usr/bin/env bash
# run_cache_unit_test.sh — compile and run the standalone SimpleDataCache unit test.
set -euo pipefail

LYNN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$LYNN/external/RISC-V-Pipelined-Processor"
INC="$CORE/incdir"
RTL="$LYNN/rtl"
TB="$LYNN/tests/cache/cache_unit_tb.sv"
OUT="$LYNN/work/cache_unit"
LOG="$OUT/cache_unit.log"

mkdir -p "$OUT"

echo "[cache-unit] building..."
verilator --binary --timing -j 0 \
    --top-module cache_unit_tb \
    +define+XLEN32 \
    --timescale 1ns/1ps \
    -Wno-TIMESCALEMOD -Wno-WIDTH -Wno-CASEX -Wno-UNUSEDSIGNAL \
    -Wno-VARHIDDEN -Wno-DECLFILENAME -Wno-CASEINCOMPLETE -Wno-fatal \
    -I"$INC" -I"$RTL" \
    "$RTL/SimpleDataCache.sv" "$TB" \
    --Mdir "$OUT/obj_dir" -o Vcache_unit >/dev/null 2>&1

echo "[cache-unit] running..."
"$OUT/obj_dir/Vcache_unit" 2>&1 | tee "$LOG"

if grep -q "UNIT_TEST PASS" "$LOG"; then
    echo "[cache-unit] PASS"
    exit 0
else
    echo "[cache-unit] FAIL — see $LOG" >&2
    exit 1
fi
