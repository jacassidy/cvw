#!/usr/bin/env bash
# fetch_tools.sh — download the free synthesis toolchain into external/tools and
# a Sky130 open Liberty file into external/lib. Idempotent.
set -euo pipefail

LYNN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="$LYNN/external/tools"
LIB="$LYNN/external/lib"
mkdir -p "$TOOLS" "$LIB"

# ---- oss-cad-suite (Yosys + ABC) ----
if [[ ! -x "$TOOLS/oss-cad-suite/bin/yosys" ]]; then
    echo "[fetch-tools] downloading oss-cad-suite (Yosys+ABC)..."
    URL=$(curl -s https://api.github.com/repos/YosysHQ/oss-cad-suite-build/releases/latest \
          | grep -o 'https://[^"]*linux-x64[^"]*\.tgz' | head -1)
    curl -sL -o "$TOOLS/oss-cad-suite.tgz" "$URL"
    tar -C "$TOOLS" -xzf "$TOOLS/oss-cad-suite.tgz"
    rm -f "$TOOLS/oss-cad-suite.tgz"
else
    echo "[fetch-tools] oss-cad-suite present"
fi

# ---- sv2v ----
if [[ ! -x "$TOOLS/sv2v-Linux/sv2v" ]]; then
    echo "[fetch-tools] downloading sv2v..."
    URL=$(curl -s https://api.github.com/repos/zachjs/sv2v/releases/latest \
          | grep -o 'https://[^"]*Linux[^"]*\.zip' | head -1)
    curl -sL -o "$TOOLS/sv2v.zip" "$URL"
    ( cd "$TOOLS" && unzip -o -q sv2v.zip && rm -f sv2v.zip )
else
    echo "[fetch-tools] sv2v present"
fi

# ---- Sky130 open Liberty ----
LIBFILE="$LIB/sky130_fd_sc_hd__tt_025C_1v80.lib"
if [[ ! -f "$LIBFILE" ]]; then
    echo "[fetch-tools] downloading Sky130 Liberty..."
    curl -sL -o "$LIBFILE" \
      https://raw.githubusercontent.com/The-OpenROAD-Project/OpenROAD-flow-scripts/master/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
else
    echo "[fetch-tools] Sky130 Liberty present"
fi

echo "[fetch-tools] done."
