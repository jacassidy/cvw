#!/usr/bin/env bash
# fetch_core.sh — reproducibly fetch and pin the external processor, then apply
# the Lynn integration patch (memory backpressure). Idempotent: safe to re-run.
#
# Env: CORE_REPO CORE_REF CORE_DIR CORE_PATCH
set -euo pipefail

: "${CORE_REPO:?}"; : "${CORE_REF:?}"; : "${CORE_DIR:?}"; : "${CORE_PATCH:?}"

echo "[fetch-core] repo=$CORE_REPO"
echo "[fetch-core] ref =$CORE_REF"
echo "[fetch-core] dir =$CORE_DIR"

if [[ ! -d "$CORE_DIR/.git" ]]; then
    echo "[fetch-core] cloning..."
    mkdir -p "$(dirname "$CORE_DIR")"
    git clone --quiet "$CORE_REPO" "$CORE_DIR"
fi

cd "$CORE_DIR"

# Fetch the pinned ref if we don't already have it.
if ! git cat-file -e "${CORE_REF}^{commit}" 2>/dev/null; then
    echo "[fetch-core] fetching ref..."
    git fetch --quiet origin "$CORE_REF" || git fetch --quiet origin
fi

CURRENT=$(git rev-parse HEAD 2>/dev/null || echo none)
TARGET=$(git rev-parse "$CORE_REF" 2>/dev/null || echo "$CORE_REF")

if [[ "$CURRENT" != "$TARGET" ]]; then
    echo "[fetch-core] checking out $CORE_REF"
    git checkout --quiet --force "$CORE_REF"
fi

# Apply the integration patch idempotently: skip if already applied.
if [[ -f "$CORE_PATCH" ]]; then
    if git apply --reverse --check "$CORE_PATCH" >/dev/null 2>&1; then
        echo "[fetch-core] patch already applied — skipping"
    elif git apply --check "$CORE_PATCH" >/dev/null 2>&1; then
        echo "[fetch-core] applying $CORE_PATCH"
        git apply "$CORE_PATCH"
    else
        echo "[fetch-core] ERROR: patch does not apply cleanly to $CORE_REF" >&2
        echo "[fetch-core]        (checkout may be dirty or ref mismatched)" >&2
        exit 1
    fi
fi

echo "[fetch-core] done. HEAD=$(git rev-parse --short HEAD) (patched)"
