#!/usr/bin/env python3
# report.py — parse Lynn baseline-vs-cache results from real logs into
# results/benchmark_results.{json,csv,md}. Nothing is hand-entered; every number
# comes from a simulation or synthesis log staged by benchmark.sh.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
import csv
import json
import re
import sys
from pathlib import Path

LYNN = Path(__file__).resolve().parent.parent
RESULTS = LYNN / "results"
VARIANTS = ["baseline", "cache"]


def read(p):
    p = Path(p)
    return p.read_text(errors="ignore") if p.is_file() else ""


def test_passed(log_text):
    return ("INFO: Test Completed!" in log_text
            and not re.search(r"Test Failed|FAILED|ERROR:", log_text))


def parse_coremark(text):
    out = {"completed": test_passed(text)}
    for key, pat in [
        ("elapsed_mtime", r"Elapsed MTIME:\s*(\d+)"),
        ("elapsed_minstret", r"Elapsed MINSTRET:\s*(\d+)"),
    ]:
        m = re.search(pat, text)
        if m:
            out[key] = int(m.group(1))
    m = re.search(r"COREMARK/MHz Score:.*=\s*([\d.]+)", text)
    if m:
        out["coremark_per_mhz"] = float(m.group(1))
    m = re.search(r"CPI:.*=\s*([\d.]+)", text)
    if m:
        out["cpi"] = float(m.group(1))
    return out


def parse_cache_stats(text):
    m = re.search(r"CACHE_STATS\s+(.*)", text)
    if not m:
        return None
    stats = {}
    for tok in m.group(1).split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            try:
                stats[k] = float(v) if "." in v else int(v)
            except ValueError:
                stats[k] = v
    return stats


def parse_act4_scan(text):
    def grab(pat):
        m = re.search(pat, text)
        return int(m.group(1)) if m else None
    return {
        "total": grab(r"Total logs:\s+(\d+)"),
        "passed": grab(r"Passed:\s+(\d+)"),
        "failed": grab(r"Failed:\s+(\d+)"),
    }


def parse_synth_area(timing_txt):
    m = re.search(r"Chip area for module '\\?\w+':\s+([\d.]+)", timing_txt)
    area = float(m.group(1)) if m else None
    m = re.search(r"sequential elements:\s+([\d.]+)", timing_txt)
    seq = float(m.group(1)) if m else None
    return area, seq


def parse_synth_cells(stat_json_text):
    try:
        d = json.loads(stat_json_text)
    except Exception:
        return {}
    # yosys stat -json: {"modules": {...}, "design": {"num_cells": N, ...}}
    design = d.get("design", {})
    return {
        "num_cells": design.get("num_cells"),
        "num_cells_by_type_seq": None,  # filled below if available
    }


def parse_delay_ps(delay_txt):
    m = re.search(r"Delay\s*=\s*([\d.]+)\s*ps", delay_txt)
    return float(m.group(1)) if m else None


def synth_from_stat(stat_json_text):
    """Return (chip_area, seq_area, total_cells, seq_cells) from yosys stat -json."""
    try:
        d = json.loads(stat_json_text)
    except Exception:
        return None, None, None, None
    design = d.get("design", {})
    by_type = design.get("num_cells_by_type", {})
    # Exclude yosys pseudo-cells (e.g. $scopeinfo) from real-cell counts.
    real = {t: n for t, n in by_type.items() if not t.startswith("$")}
    total = sum(real.values()) if real else design.get("num_cells")
    seq = sum(n for t, n in real.items() if re.search(r"df|dl|sdf|latch", t, re.I)) if real else None
    return design.get("area"), design.get("sequential_area"), total, seq


def collect_variant(v):
    d = RESULTS / v
    data = {"variant": v}

    data["bringup"] = test_passed(read(d / "bringup.sim.log"))
    data["c_test"] = test_passed(read(d / "c_test.sim.log"))
    if v == "cache":
        data["cache_test"] = test_passed(read(d / "cache_test.sim.log"))
        data["cache_unit_test"] = "UNIT_TEST PASS" in read(d / "cache_unit.log")

    data["coremark"] = parse_coremark(read(d / "coremark.sim.log"))

    # Cache statistics come from the coremark (or cache-test) sim log.
    cs = parse_cache_stats(read(d / "coremark.sim.log"))
    if cs is None and v == "cache":
        cs = parse_cache_stats(read(d / "cache_test.sim.log"))
    data["cache_stats"] = cs

    data["act4"] = parse_act4_scan(read(d / "act4_scan.txt"))

    # Synthesis (from synth/work/<variant>)
    sdir = LYNN / "synth" / "work" / v
    area, seq_area, total_cells, seq_cells = synth_from_stat(read(sdir / "stat.json"))
    if area is None:  # fall back to the human-readable stat report
        area, seq_area = parse_synth_area(read(sdir / "timing.txt"))
    delay = parse_delay_ps(read(sdir / "abc_delay.txt"))
    data["synth"] = {
        "chip_area_um2": area,
        "sequential_area_um2": seq_area,
        "total_cells": total_cells,
        "sequential_cells": seq_cells,
        "combinational_cells": (total_cells - seq_cells) if (total_cells and seq_cells) else None,
        "critical_path_ps": delay,
        "note": "Data array inferred as flip-flops + muxes, NOT a compiled SRAM macro.",
    }
    return data


def main():
    RESULTS.mkdir(exist_ok=True)
    meta = {}
    meta_path = RESULTS / "meta.json"
    if meta_path.is_file():
        meta = json.loads(read(meta_path))

    results = {v: collect_variant(v) for v in VARIANTS}

    # Derived comparisons
    cmp = {}
    b = results["baseline"]["coremark"].get("elapsed_mtime")
    c = results["cache"]["coremark"].get("elapsed_mtime")
    if b and c:
        cmp["coremark_mtime_baseline"] = b
        cmp["coremark_mtime_cache"] = c
        cmp["coremark_mtime_delta"] = c - b
        cmp["cache_speedup"] = round(b / c, 4)  # >1 faster, <1 slower
    ba = results["baseline"]["synth"].get("chip_area_um2")
    ca = results["cache"]["synth"].get("chip_area_um2")
    if ba and ca:
        cmp["area_overhead_pct"] = round((ca - ba) / ba * 100, 1)
    bp = results["baseline"]["synth"].get("critical_path_ps")
    cp = results["cache"]["synth"].get("critical_path_ps")
    if bp and cp:
        cmp["timing_change_pct"] = round((cp - bp) / bp * 100, 1)

    out = {"meta": meta, "variants": results, "comparison": cmp}

    # ---- JSON ----
    (RESULTS / "benchmark_results.json").write_text(json.dumps(out, indent=2))

    # ---- CSV ----
    with open(RESULTS / "benchmark_results.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["metric", "baseline", "cache"])
        def row(name, bv, cv):
            w.writerow([name, bv, cv])
        row("bringup_pass", results["baseline"]["bringup"], results["cache"]["bringup"])
        row("c_test_pass", results["baseline"]["c_test"], results["cache"]["c_test"])
        row("cache_unit_test_pass", "-", results["cache"].get("cache_unit_test"))
        row("cache_test_pass", "-", results["cache"].get("cache_test"))
        row("act4_total", results["baseline"]["act4"]["total"], results["cache"]["act4"]["total"])
        row("act4_passed", results["baseline"]["act4"]["passed"], results["cache"]["act4"]["passed"])
        row("act4_failed", results["baseline"]["act4"]["failed"], results["cache"]["act4"]["failed"])
        row("coremark_mtime", results["baseline"]["coremark"].get("elapsed_mtime"),
            results["cache"]["coremark"].get("elapsed_mtime"))
        row("coremark_minstret", results["baseline"]["coremark"].get("elapsed_minstret"),
            results["cache"]["coremark"].get("elapsed_minstret"))
        row("coremark_per_mhz", results["baseline"]["coremark"].get("coremark_per_mhz"),
            results["cache"]["coremark"].get("coremark_per_mhz"))
        cs = results["cache"].get("cache_stats") or {}
        for k in ["accesses", "read_hits", "read_misses", "store_hits",
                  "store_misses", "refills", "refill_cycles", "stall_cycles",
                  "uncached", "hit_rate"]:
            row(f"cache_{k}", "-", cs.get(k))
        row("synth_chip_area_um2", results["baseline"]["synth"]["chip_area_um2"],
            results["cache"]["synth"]["chip_area_um2"])
        row("synth_total_cells", results["baseline"]["synth"]["total_cells"],
            results["cache"]["synth"]["total_cells"])
        row("synth_seq_cells", results["baseline"]["synth"]["sequential_cells"],
            results["cache"]["synth"]["sequential_cells"])
        row("synth_critical_path_ps", results["baseline"]["synth"]["critical_path_ps"],
            results["cache"]["synth"]["critical_path_ps"])

    # ---- Markdown ----
    md = md_report(out)
    (RESULTS / "benchmark_results.md").write_text(md)

    print("Wrote:")
    for ext in ("json", "csv", "md"):
        print(f"  {RESULTS / ('benchmark_results.' + ext)}")
    print()
    print(md)
    return 0


def fmt(x):
    if x is None:
        return "n/a"
    if isinstance(x, bool):
        return "PASS" if x else "FAIL"
    if isinstance(x, float):
        return f"{x:,.2f}" if x > 100 else f"{x:.4f}"
    if isinstance(x, int):
        return f"{x:,}"
    return str(x)


def md_report(out):
    b = out["variants"]["baseline"]
    c = out["variants"]["cache"]
    cmp = out["comparison"]
    L = []
    L.append("# Lynn Baseline vs. Cache — Benchmark Report\n")
    meta = out.get("meta", {})
    if meta:
        L.append(f"- Processor commit: `{meta.get('core_commit', '?')}`")
        L.append(f"- Generated: {meta.get('timestamp', '?')}")
        L.append("")

    L.append("## Functional results\n")
    L.append("| Test | Baseline | Cache |")
    L.append("|------|----------|-------|")
    L.append(f"| Bring-up | {fmt(b['bringup'])} | {fmt(c['bringup'])} |")
    L.append(f"| C test | {fmt(b['c_test'])} | {fmt(c['c_test'])} |")
    L.append(f"| Cache unit test | n/a | {fmt(c.get('cache_unit_test'))} |")
    L.append(f"| Processor cache test | n/a | {fmt(c.get('cache_test'))} |")
    L.append(f"| ACT4 total | {fmt(b['act4']['total'])} | {fmt(c['act4']['total'])} |")
    L.append(f"| ACT4 passed | {fmt(b['act4']['passed'])} | {fmt(c['act4']['passed'])} |")
    L.append(f"| ACT4 failed | {fmt(b['act4']['failed'])} | {fmt(c['act4']['failed'])} |")
    L.append("")

    L.append("## CoreMark\n")
    L.append("| Metric | Baseline | Cache |")
    L.append("|--------|----------|-------|")
    L.append(f"| Completed | {fmt(b['coremark'].get('completed'))} | {fmt(c['coremark'].get('completed'))} |")
    L.append(f"| Elapsed MTIME (cycles) | {fmt(b['coremark'].get('elapsed_mtime'))} | {fmt(c['coremark'].get('elapsed_mtime'))} |")
    L.append(f"| Elapsed MINSTRET | {fmt(b['coremark'].get('elapsed_minstret'))} | {fmt(c['coremark'].get('elapsed_minstret'))} |")
    L.append(f"| CoreMark/MHz | {fmt(b['coremark'].get('coremark_per_mhz'))} | {fmt(c['coremark'].get('coremark_per_mhz'))} |")
    if "cache_speedup" in cmp:
        L.append(f"| MTIME delta (cache-baseline) | | {fmt(cmp['coremark_mtime_delta'])} |")
        sp = cmp["cache_speedup"]
        verdict = "faster" if sp > 1 else "slower"
        L.append(f"| Cache speedup (baseline/cache) | | {sp:.4f}x ({verdict}) |")
    L.append("")

    cs = c.get("cache_stats") or {}
    L.append("## Cache statistics (from CoreMark run)\n")
    if cs:
        L.append("| Stat | Value |")
        L.append("|------|-------|")
        for k in ["accesses", "read", "write", "read_hits", "read_misses",
                  "store_hits", "store_misses", "refills", "refill_cycles",
                  "stall_cycles", "uncached", "hit_rate"]:
            if k in cs:
                L.append(f"| {k} | {fmt(cs[k])} |")
    else:
        L.append("_No cache statistics (cache variant only)._")
    L.append("")

    L.append("## Synthesis (Yosys + Sky130, free flow)\n")
    L.append("| Metric | Baseline | Cache |")
    L.append("|--------|----------|-------|")
    L.append(f"| Chip area (µm²) | {fmt(b['synth']['chip_area_um2'])} | {fmt(c['synth']['chip_area_um2'])} |")
    L.append(f"| Total cells | {fmt(b['synth']['total_cells'])} | {fmt(c['synth']['total_cells'])} |")
    L.append(f"| Sequential cells | {fmt(b['synth']['sequential_cells'])} | {fmt(c['synth']['sequential_cells'])} |")
    L.append(f"| Combinational cells | {fmt(b['synth']['combinational_cells'])} | {fmt(c['synth']['combinational_cells'])} |")
    L.append(f"| Critical path est. (ps) | {fmt(b['synth']['critical_path_ps'])} | {fmt(c['synth']['critical_path_ps'])} |")
    if "area_overhead_pct" in cmp:
        L.append(f"| Area overhead | | {cmp['area_overhead_pct']}% |")
    if "timing_change_pct" in cmp:
        L.append(f"| Timing change | | {cmp['timing_change_pct']}% |")
    L.append("")
    L.append("> **Note:** The cache data array is inferred as flip-flops and "
             "multiplexers, **not** a compiled SRAM macro. Its area and delay are "
             "therefore much larger than a real SRAM-backed cache and are not "
             "representative of a production cache. The critical-path figure is a "
             "free-tool ABC estimate, not a sign-off STA result.")
    L.append("")
    return "\n".join(L)


if __name__ == "__main__":
    sys.exit(main())
