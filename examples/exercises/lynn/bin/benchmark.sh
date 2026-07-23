#!/usr/bin/env bash
# benchmark.sh — run the full baseline-vs-cache comparison and stage every log
# into results/<variant>/ for report.py to parse. Reuses the Make targets so the
# measured numbers come from the exact same flow a user runs by hand.
set -uo pipefail

LYNN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$LYNN"
RESULTS="$LYNN/results"
mkdir -p "$RESULTS"

MAKE="make --no-print-directory"

stage() {  # stage <src> <dst>
    [[ -f "$1" ]] && cp -f "$1" "$2" || true
}

run_variant() {
    local V=$1
    local OUT="$RESULTS/$V"
    mkdir -p "$OUT"
    echo "==================================================================="
    echo " BENCHMARK: $V"
    echo "==================================================================="

    $MAKE CORE_VARIANT=$V build

    echo "--- bringup ---"
    $MAKE CORE_VARIANT=$V bringup_test || true
    stage "$LYNN/tests/bringup/work/bringup.elf.sim.log" "$OUT/bringup.sim.log"

    echo "--- C test ---"
    $MAKE CORE_VARIANT=$V C_test || true
    stage "$LYNN/tests/C/work/c_test.elf.sim.log" "$OUT/c_test.sim.log"

    if [[ "$V" == "cache" ]]; then
        echo "--- cache unit test ---"
        $MAKE CORE_VARIANT=$V cache-unit-test || true
        stage "$LYNN/work/cache_unit/cache_unit.log" "$OUT/cache_unit.log"

        echo "--- processor cache test ---"
        $MAKE CORE_VARIANT=$V cache-test || true
        stage "$LYNN/tests/cache/work/cache_test.elf.sim.log" "$OUT/cache_test.sim.log"
    fi

    echo "--- ACT4 ---"
    $MAKE CORE_VARIANT=$V test 2>&1 | tee "$OUT/act4_scan.txt" || true

    echo "--- CoreMark ---"
    $MAKE CORE_VARIANT=$V coremark || true
    stage "$LYNN/coremark/work/coremark.bare.riscv.elf.sim.log" "$OUT/coremark.sim.log"

    echo "--- Synthesis ---"
    $MAKE CORE_VARIANT=$V synth || true
}

# Record provenance / tool versions.
record_meta() {
    local core_commit
    core_commit=$(git -C "$LYNN/external/RISC-V-Pipelined-Processor" rev-parse HEAD 2>/dev/null || echo unknown)
    python3 - "$RESULTS/meta.json" "$core_commit" <<'PY'
import json, subprocess, sys, datetime, shutil
meta_path, core_commit = sys.argv[1], sys.argv[2]
def ver(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=15).stdout.strip().splitlines()[0]
    except Exception:
        try:
            return subprocess.run(cmd, capture_output=True, text=True, timeout=15).stderr.strip().splitlines()[0]
        except Exception:
            return "unknown"
meta = {
    "timestamp": datetime.datetime.now().isoformat(timespec="seconds"),
    "core_commit": core_commit,
    "tools": {
        "verilator": ver(["verilator", "--version"]),
        "gcc": ver(["riscv64-unknown-elf-gcc", "--version"]),
        "yosys": ver(["yosys", "--version"]),
        "sv2v": ver(["sv2v", "--version"]),
        "sail": ver(["sail_riscv_sim", "--version"]),
        "python": ver(["python3", "--version"]),
    },
    "commands": [
        "make CORE_VARIANT=<v> build",
        "make CORE_VARIANT=<v> bringup_test C_test test coremark synth",
        "make CORE_VARIANT=cache cache-unit-test cache-test",
    ],
}
json.dump(meta, open(meta_path, "w"), indent=2)
print("wrote", meta_path)
PY
}

for V in baseline cache; do
    run_variant "$V"
done

# meta must reflect the ACTUAL build toolchain: $RISCV/bin (GCC/newlib) first for
# gcc, the system verilator used by the sim flow, plus the vendored synth tools.
export PATH="${RISCV:+$RISCV/bin:}$PATH:$LYNN/external/tools/oss-cad-suite/bin:$LYNN/external/tools/sv2v-Linux:$LYNN/external/tools/sail010/sail-riscv-Linux-x86_64/bin"
record_meta

echo
echo "Generating report..."
python3 "$LYNN/bin/report.py"
