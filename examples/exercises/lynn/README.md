# Lynn — Local Cache-Development Environment

A fully local, free-tool workflow for developing and evaluating a data cache on
the [jacassidy/RISC-V-Pipelined-Processor](https://github.com/jacassidy/RISC-V-Pipelined-Processor)
RV32 core inside CORE-V Wally. Simulation uses **Verilator**; synthesis uses
**Yosys + ABC + open Sky130**. No Questa/ModelSim, Design Compiler, or cloud
tools are required for the default flow.

It builds two configurations from the *same* processor revision:

- **`baseline`** — the unmodified `TestingCore` wrapper (direct memory, no cache).
- **`cache`** — the new `TestingCacheCore` wrapper with a blocking direct-mapped
  write-through data cache (`SimpleDataCache`) and a proper memory-backpressure
  stall through the pipeline.

---

## 1. Operating-system assumptions

- Linux x86-64 (tested on Ubuntu-family, kernel 7.x).
- `bash`, `git`, `curl`, `tar`, `unzip`, GNU `make`.
- Network access for the one-time `make fetch-core` / `make fetch-tools`.
- No `sudo` required; all extra tools install under `external/` or `~/.local`.

## 2. Required free tools

| Tool | Used for | Provided by |
|------|----------|-------------|
| Verilator (≥ 5.0) | RTL simulation | system package |
| RISC-V GNU toolchain (GCC ≥ 15, newlib) | building test/benchmark ELFs | `$RISCV/bin` (CVW toolchain) |
| `elf2hex` | ELF → memfile | `$WALLY/bin` (CVW) |
| Python 3 | scripts / reports | system |
| Yosys + ABC | synthesis + timing estimate | `make fetch-tools` (oss-cad-suite) |
| sv2v | SystemVerilog → Verilog for Yosys | `make fetch-tools` |
| Sky130 open Liberty | standard-cell library | `make fetch-tools` |
| Sail RISC-V model **0.10** | ACT4 reference signatures | `make fetch-tools` |
| mise (+ Ruby 3.4, uv) | ACT4 test generation (UDB) | auto-installed to `~/.local` |

Run **`make doctor`** to check them all.

## 3. One-time CVW setup

```bash
cd ~/cvw            # your CORE-V Wally checkout
source setup.sh     # sets $WALLY, $RISCV, PATH, venv  (run every shell session)
cd examples/exercises/lynn
```

## 4. Check the environment

```bash
make doctor
```
Reports OK/MISS for every required tool, the selected Liberty file, and the
processor checkout, with an actionable hint for anything missing.

## 5. Fetch the processor (and free tools)

```bash
make fetch-tools    # one-time: Yosys/ABC, sv2v, Sky130 Liberty, Sail 0.10
make fetch-core     # clone + pin + patch the external processor (idempotent)
```

- Pinned commit: **`52d2dd9edc2441ab000bd30bc0bbff5fc247f560`** (see `CORE_REF`).
- Cloned to `external/RISC-V-Pipelined-Processor` (git-ignored).
- The integration patch `patches/0001-external-membackpressure.patch` is applied
  idempotently after checkout (adds `External_MemStall`, guards simulation-only
  system tasks for synthesis). Re-running `make fetch-core` is safe.

Configuration knobs (all overridable on the command line):

```make
SIM          ?= verilator
CORE_VARIANT ?= cache            # baseline | cache
XLEN         ?= 32
ARCH         ?= rv32i_zicsr
TRACE        ?= 0                # 1 = FST waveform
SYNTH_TOOL   ?= yosys            # yosys | dc (legacy)
CORE_REPO    ?= https://github.com/jacassidy/RISC-V-Pipelined-Processor.git
CORE_REF     ?= 52d2dd9edc2441ab000bd30bc0bbff5fc247f560
CORE_DIR     ?= $(CURDIR)/external/RISC-V-Pipelined-Processor
LIBERTY_FILE ?= external/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
```

## 6. Run the uncached baseline

```bash
make CORE_VARIANT=baseline lint
make CORE_VARIANT=baseline build
make CORE_VARIANT=baseline bringup_test
make CORE_VARIANT=baseline C_test
make CORE_VARIANT=baseline test        # ACT4 architecture suite
make CORE_VARIANT=baseline coremark
make CORE_VARIANT=baseline synth
```

## 7. Run the cached core

```bash
make CORE_VARIANT=cache lint
make CORE_VARIANT=cache build
make CORE_VARIANT=cache cache-unit-test # standalone RTL cache unit test
make CORE_VARIANT=cache cache-test      # processor-level cache exercise
make CORE_VARIANT=cache bringup_test
make CORE_VARIANT=cache C_test
make CORE_VARIANT=cache test
make CORE_VARIANT=cache coremark
make CORE_VARIANT=cache synth
```

Run any ELF directly (baseline or cache):

```bash
make CORE_VARIANT=cache run ELFS="path/to/a.elf path/to/b.elf"
make CORE_VARIANT=cache run TRACE=1 ELFS="a.elf"   # + wave.fst (GTKWave/Surfer)
make CORE_VARIANT=cache run SAIL=1 ELFS="a.elf"    # Sail reference model
```

## 8. Unit tests

- **`make cache-unit-test`** — compiles `tests/cache/cache_unit_tb.sv` against
  `SimpleDataCache` with a tiny behavioral memory and checks all 14 required
  behaviors (reset invalidation, first-miss, hit, same-line words, conflict
  eviction, store-hit byte update, store-miss write-through, byte/halfword
  preservation, requested-word-on-refill, uncached no-allocate, single stall
  resolution, single backing store, no lost request). Prints `UNIT_TEST PASS`.
- **`make cache-test`** — a self-checking assembly program run through the Lynn
  testbench exercising the same behaviors on the real processor + cache.

## 9. ACT4 architecture suite

```bash
make CORE_VARIANT=<v> test
```
Generates the RISC-V architecture tests (UDB test-gen + Sail 0.10 reference
signatures), runs every ELF on the selected core, and scans the logs. The
generation step needs mise/Ruby/Sail (installed by `fetch-tools`).

## 10. CoreMark

```bash
make CORE_VARIANT=<v> coremark
```
Builds CoreMark (`-O3`, 10 iterations) and runs it; the port prints
`Elapsed MTIME`, `Elapsed MINSTRET`, `COREMARK/MHz Score`, and `CPI`.

## 11. Synthesis

```bash
make CORE_VARIANT=<v> synth
```
`sv2v` (with `SYNTHESIS` defined) flattens the RTL to Verilog; Yosys elaborates
the top, checks the hierarchy, runs `synth`, maps flops and logic to Sky130 via
ABC, and writes:

```
synth/work/<variant>/
  flat.v                     sv2v output
  <top>_netlist.v            mapped gate netlist
  stat.json                  machine-readable cell/area stats
  timing.txt                 human-readable stat report
  abc_delay.txt              ABC stime critical-path estimate (ps)
  yosys.log
```

## 12. Comparison report

```bash
make benchmark      # runs both variants end-to-end, stages every log
make report         # parses staged logs -> results/benchmark_results.{json,csv,md}
```
`results/benchmark_results.md` holds the compact baseline-vs-cache table. All
numbers are parsed from real logs — nothing is typed in by hand.

---

## 13. Cache geometry and policies

```
Organization       : direct mapped
Capacity           : 1 KiB
Line size          : 16 bytes (4 × 32-bit words)
Lines              : 64
Word size          : 32 bits
Read policy        : allocate on read miss
Write policy       : write-through
Write allocation   : no write allocate
Outstanding misses : one (blocking)
Instruction cache  : none (fetch is uncached, same as baseline)
Replacement        : implicit (direct-mapped)
```
Geometry is parameterized in `rtl/SimpleDataCache.sv`
(`LINE_BYTES`, `NUM_LINES`, `CACHEABLE_BASE`, `CACHEABLE_SIZE`).

## 14. Address decomposition (32-bit byte address, default geometry)

```
 31                          10 9        4 3      2 1     0
+------------------------------+-----------+--------+------+
|            tag (22)          | index (6) | word(2)|byte(2)|
+------------------------------+-----------+--------+------+
byte/word offset : bits [3:0]  (4 bits: word-in-line [3:2], byte-in-word [1:0])
index            : bits [9:4]  (6 bits → 64 lines)
tag              : bits [31:10]
```

## 15. Miss / refill state machine

A single `busy` flag plus a 2-bit `refill_idx` implement a blocking refill:

```
IDLE (busy=0):
  read hit            -> return data_arr[index][word], no stall
  read miss (cache-   -> Stall=1; latch index/tag/line base; busy<=1; refill_idx<=0
    able)
  store               -> write-through to memory (1 cycle); if hit, update
                         cached bytes; no stall; no allocate on miss
  uncached access     -> pass straight through to memory; no stall; no allocate

REFILL (busy=1), 4 cycles, Stall=1 throughout:
  each cycle drives mem address = line_base + refill_idx*4 and latches the word;
  on the 4th word install the whole line (tag + valid), busy<=0.

Back in IDLE the same (still-stalled) access now HITS and returns the
originally requested word; the PC and all commits advance exactly once.
```
The backing memory returns data combinationally, but the refill is modeled as an
explicit 4-cycle sequence so the miss penalty is real and the design can later
drive a realistic (multi-cycle) memory port.

## 16. Pipeline stall / backpressure design

The core is single-cycle (`PIPELINED` undefined): every instruction fetches,
executes, and commits in one clock. Backpressure is therefore a **full-core hold
with one-time commit gating**, driven by one signal:

```systemverilog
input logic External_MemStall;   // active high, from the cache
```

While `External_MemStall` is asserted (`Stall` from the cache), the patch gates
every architectural side effect so the stalled load commits exactly once:

- **PC** does not advance (`_IStage.sv`).
- **Register-file write** is gated: `RegWrite_W & ~External_MemStall`.
- **CSR write-enable** is gated: `CSREn_C & ~External_MemStall`.
- **Retirement** (`minstret`) is gated: `ValidInstruction_W & ~External_MemStall`.

Because the core is single-cycle there are no younger in-flight instructions to
overtake the blocked load, and no store is emitted during a load-miss stall
(`MemWriteEn` is forced low by the cache during refill). The result guarantees:
the load is neither lost nor executed twice, register/CSR writes commit once,
`minstret` counts once, and stores are emitted exactly once. `rdcycle`/`rdtime`
keep counting during the stall (architecturally correct — cycles still pass).

Assertions in `SimpleDataCache` catch a store issued during refill (duplicate
risk) and an out-of-range refill index.

## 17. MMIO / uncached bypass policy

Any address **outside** `[CACHEABLE_BASE, CACHEABLE_BASE+CACHEABLE_SIZE)` is
uncached. With the defaults (`CACHEABLE_BASE = 0x8000_0000`,
`CACHEABLE_SIZE = 0x0400_0000`, i.e. a 64 MiB window over main memory), this
covers the MMIO timer at `0x0200_BFF8` and any other low-address peripheral.
Uncached accesses are passed straight to backing memory: never allocated, never
stalled, and reads are not served from cache. Write-through guarantees that
completion/`tohost` stores always reach backing memory where the testbench
observes them.

## 18. Known limitations

- **Cache data array is flip-flops + muxes, not an SRAM macro.** Under Yosys it
  synthesizes to registers and a large read mux, so the cache variant's area and
  critical-path numbers are far larger than a real SRAM-backed cache. They are
  reported honestly and are **not** representative of a compiled-SRAM design.
- The critical-path figure is a free-tool **ABC `stime` estimate**, not sign-off
  static timing.
- Backing memory returns data combinationally; the 4-cycle refill penalty is
  modeled, not derived from a realistic DRAM/AXI latency.
- Instruction fetch is uncached (data cache only, as specified for v1).
- Because the baseline enjoys single-cycle "magic" memory, the cache adds miss
  penalty and typically **increases** CoreMark cycle count — the comparison is
  reported transparently (speedup may be < 1).
- ACT4 generation pins **Sail 0.10** (the framework requires that exact version
  string) and needs mise/Ruby/uv; these are fetched automatically.

## 19. Extending the cache (for the next engineer)

- **Change geometry**: edit the `SimpleDataCache` parameters (`NUM_LINES`,
  `LINE_BYTES`) — index/tag/offset widths are derived automatically.
- **Set associativity**: add a way dimension to `valid_arr/tag_arr/data_arr`,
  a way-select mux on hit, and a replacement policy (e.g. LRU/PLRU) for refill.
- **Write-back**: add a dirty bit per line, evict-before-refill on a dirty miss,
  and a write-back path in the refill FSM.
- **Instruction cache**: instantiate a second `SimpleDataCache` (read-only) on
  the fetch port and OR its stall into `External_MemStall`.
- **Realistic memory**: replace the combinational refill reads with a valid/ready
  handshake to a latency model; the FSM already sequences one word per cycle.
- **Statistics**: counters live under `` `ifndef SYNTHESIS `` so they never affect
  area; add new ones there and extend the `CACHE_STATS` print + `bin/report.py`.

---

## File map

```
Makefile                     top-level free flow (Verilator + Yosys)
rtl/
  TestingCacheCore.sv        cached wrapper (testingCacheCore)
  SimpleDataCache.sv         the cache + stats + assertions
patches/
  0001-external-membackpressure.patch   External_MemStall + synth guards
bin/
  doctor.py  fetch_core.sh  fetch_tools.sh  run_verilator.sh
  run_cache_unit_test.sh  benchmark.sh  report.py  score.py  scan_test_logs.py
synth/
  Makefile  run_yosys.sh     free synthesis driver
tests/
  bringup/  C/  act4/  cache/ (cache_test.S + cache_unit_tb.sv)
tb/
  testbench.sv  ram1p1rwb.sv (authoritative ELF loader / completion detector)
results/                     benchmark_results.{json,csv,md}, meta.json
```

## Legacy commercial tools (optional)

The original Questa/Design-Compiler paths are preserved but off by default:
`make ... synth SYNTH_TOOL=dc` uses `$WALLY/synthDC` (Synopsys DC) if available.
The default `build`/`run`/`synth` never require them.
