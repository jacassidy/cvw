#!/usr/bin/env bash
# run_yosys.sh — free local synthesis of a Lynn processor top with sv2v + Yosys + ABC.
# Lynn cache-development exercise.
#
# Steps:
#   1. sv2v converts all SystemVerilog (packages first, incdir honoured) to one
#      Verilog file, with SYNTHESIS defined so simulation-only counters/$display
#      are stripped (they must not inflate area/timing).
#   2. Yosys elaborates the chosen top, checks the hierarchy, runs generic synth,
#      maps flops + logic to the Sky130 standard cells via ABC, and reports.
#
# Env (all provided by synth/Makefile):
#   CORE_VARIANT PROCESSOR_SRC WRAPPER_DIR INC_DIR SYNTH_TOP XLEN LIBERTY_FILE WORK_DIR
set -euo pipefail

: "${CORE_VARIANT:?}"; : "${PROCESSOR_SRC:?}"; : "${INC_DIR:?}"; : "${SYNTH_TOP:?}"
: "${LIBERTY_FILE:?}"; : "${WORK_DIR:?}"
XLEN="${XLEN:-32}"
WRAPPER_DIR="${WRAPPER_DIR:-}"

OUT="$WORK_DIR/$CORE_VARIANT"
mkdir -p "$OUT"
FLAT="$OUT/flat.v"
NETLIST="$OUT/${SYNTH_TOP}_netlist.v"
STATRPT="$OUT/stat.json"
TIMERPT="$OUT/timing.txt"
LOG="$OUT/yosys.log"

if [[ ! -f "$LIBERTY_FILE" ]]; then
    echo "ERROR: Liberty file not found: $LIBERTY_FILE" >&2
    echo "       Set LIBERTY_FILE=... or run 'make fetch-tools'." >&2
    exit 2
fi

# ---- Gather sources: packages first, then all module SV, then wrappers ----
PKGS=$(find "$PROCESSOR_SRC" -name '*.pkg' | sort)
SRCS=$(find "$PROCESSOR_SRC" -name '*.sv' | sort)
WRAP=""
if [[ "$CORE_VARIANT" == "cache" && -n "$WRAPPER_DIR" ]]; then
    WRAP="$WRAPPER_DIR/SimpleDataCache.sv $WRAPPER_DIR/TestingCacheCore.sv"
fi

echo "[synth] sv2v -> $FLAT (SYNTHESIS defined, top=$SYNTH_TOP)"
# sv2v reads .pkg via -I list; give it the incdir and pass all files.
sv2v \
    --define=SYNTHESIS \
    --define=XLEN$XLEN \
    -I"$INC_DIR" \
    --top="$SYNTH_TOP" \
    $PKGS $SRCS $WRAP \
    > "$FLAT" 2> "$OUT/sv2v.log" || { echo "ERROR: sv2v failed — see $OUT/sv2v.log" >&2; tail -20 "$OUT/sv2v.log" >&2; exit 1; }

# ---- Yosys synthesis ----
echo "[synth] yosys ($SYNTH_TOP -> Sky130)"
yosys -q -l "$LOG" -p "
    read_verilog -sv $FLAT
    hierarchy -check -top $SYNTH_TOP
    synth -top $SYNTH_TOP -flatten
    dfflibmap -liberty $LIBERTY_FILE
    abc -liberty $LIBERTY_FILE
    opt_clean
    setundef -zero
    write_verilog $NETLIST
    tee -o $STATRPT stat -json -liberty $LIBERTY_FILE
    tee -o $TIMERPT stat -liberty $LIBERTY_FILE
" 2>&1 | tail -3 || { echo "ERROR: yosys failed — see $LOG" >&2; tail -30 "$LOG" >&2; exit 1; }

# ---- Timing estimate via ABC stime (longest register-to-register path) ----
# ABC maps to the Liberty cells and reports the critical-path delay in ps.
# This is a static estimate from a free tool, NOT a sign-off STA result.
echo "[synth] estimating critical path via ABC stime"
ABC_SCR="$OUT/abc_stime.scr"
printf 'strash\ndch\nmap\ntopo\nstime -p\n' > "$ABC_SCR"
yosys -p "
    read_verilog -sv $FLAT
    synth -top $SYNTH_TOP -flatten
    dfflibmap -liberty $LIBERTY_FILE
    abc -liberty $LIBERTY_FILE -script $ABC_SCR
" 2>&1 | grep -iE 'Delay *=' | tail -1 > "$OUT/abc_delay.txt" || true
echo "[synth] critical-path estimate: $(cat "$OUT/abc_delay.txt")"

echo "[synth] done. netlist=$NETLIST stat=$STATRPT"
