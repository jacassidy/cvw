#!/usr/bin/env python3
# doctor.py — check that the free-tool environment for the Lynn flow is present.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
import os
import shutil
import subprocess
import sys
from pathlib import Path

LYNN = Path(__file__).resolve().parent.parent
EXT_TOOLS = LYNN / "external" / "tools"

# Make the vendored tools discoverable for the check.
os.environ["PATH"] = os.pathsep.join([
    str(EXT_TOOLS / "oss-cad-suite" / "bin"),
    str(EXT_TOOLS / "sv2v-Linux"),
    os.environ.get("PATH", ""),
])

GREEN, RED, YEL, END = "\033[92m", "\033[91m", "\033[93m", "\033[0m"


def ver(cmd):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        return (out.stdout + out.stderr).strip().splitlines()[0]
    except Exception:
        return ""


def check(name, exe, required=True, version_cmd=None, hint=""):
    path = shutil.which(exe)
    if path:
        v = ver(version_cmd) if version_cmd else ""
        print(f"  {GREEN}OK{END}   {name:22} {path}  {v[:48]}")
        return True
    tag = f"{RED}MISS{END}" if required else f"{YEL}WARN{END}"
    print(f"  {tag} {name:22} not found. {hint}")
    return not required


def check_file(name, path, required=True, hint=""):
    if Path(path).is_file():
        print(f"  {GREEN}OK{END}   {name:22} {path}")
        return True
    tag = f"{RED}MISS{END}" if required else f"{YEL}WARN{END}"
    print(f"  {tag} {name:22} not found: {path}. {hint}")
    return not required


def main():
    print("Lynn environment doctor")
    print("=" * 60)
    ok = True

    # Simulation toolchain
    ok &= check("Verilator", "verilator", True, ["verilator", "--version"],
                "Install verilator (apt install verilator or from source).")
    ok &= check("RISC-V GCC", "riscv64-unknown-elf-gcc", True,
                ["riscv64-unknown-elf-gcc", "--version"],
                "Install the RISC-V GNU toolchain (source cvw setup.sh).")
    ok &= check("objcopy", "riscv64-unknown-elf-objcopy", True)
    ok &= check("readelf", "riscv64-unknown-elf-readelf", True)
    ok &= check("Python 3", "python3", True, ["python3", "--version"])
    ok &= check("uv", "uv", False, ["uv", "--version"],
                "Optional: used by elf2hex/scan scripts.")

    # elf2hex may be on PATH ($WALLY/bin) or invoked via uv.
    wally = os.environ.get("WALLY", "")
    if shutil.which("elf2hex"):
        ok &= check("elf2hex", "elf2hex", True)
    elif wally and Path(wally, "bin", "elf2hex").is_file():
        print(f"  {GREEN}OK{END}   {'elf2hex':22} {wally}/bin/elf2hex (via uv)")
    else:
        print(f"  {RED}MISS{END} {'elf2hex':22} not found. Source cvw setup.sh.")
        ok = False

    # Synthesis toolchain (vendored under external/tools)
    ok &= check("Yosys", "yosys", True, ["yosys", "--version"],
                "Run: make fetch-tools  (or install oss-cad-suite).")
    ok &= check("ABC (yosys-abc)", "yosys-abc", True, None,
                "Ships with Yosys / oss-cad-suite.")
    ok &= check("sv2v", "sv2v", True, ["sv2v", "--version"],
                "SystemVerilog->Verilog for the Yosys flow.")

    # Liberty file
    lib = os.environ.get("LIBERTY_FILE",
                         str(LYNN / "external" / "lib" /
                             "sky130_fd_sc_hd__tt_025C_1v80.lib"))
    ok &= check_file("Sky130 Liberty", lib, True,
                     "Set LIBERTY_FILE or run make fetch-tools.")

    # External processor checkout
    core = LYNN / "external" / "RISC-V-Pipelined-Processor" / "src" / "ComputeCore.sv"
    check_file("Processor checkout", str(core), False,
               "Run: make fetch-core")

    print("=" * 60)
    if ok:
        print(f"{GREEN}Environment looks good for the free Lynn flow.{END}")
        return 0
    print(f"{RED}Missing required tools — see above.{END}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
