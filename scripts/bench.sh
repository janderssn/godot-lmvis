#!/bin/bash
# Run the in-engine benchmark and print frame-time summary.
#
# Usage:
#   scripts/bench.sh                 # run with default godot binary in PATH
#   GODOT=godot4 scripts/bench.sh    # specify which Godot binary to use
#
# The scene runs a fixed 2 s warmup + 15 s deterministic camera path
# around Åreskutan, then prints lines prefixed "BENCH" to stdout and
# quits. Compare across branches/optimizations by running on each and
# diffing the BENCH lines.

set -euo pipefail

GODOT="${GODOT:-godot4}"
cd "$(dirname "$0")/.."

if ! command -v "$GODOT" >/dev/null 2>&1; then
    if [ -x "/home/joel/bin/godot4" ]; then
        GODOT="/home/joel/bin/godot4"
    else
        echo "godot binary not found — set GODOT=/path/to/godot4 or add to PATH" >&2
        exit 1
    fi
fi

# Capture full output, surface BENCH lines.
LOG="$(mktemp -t lmvis-bench-XXXX.log)"
"$GODOT" --path . -- --bench >"$LOG" 2>&1
status=$?

grep -E "^BENCH" "$LOG" || true

if [ $status -ne 0 ]; then
    echo
    echo "Godot exited with status $status — full log:" >&2
    cat "$LOG" >&2
fi

exit $status
