#!/usr/bin/env bash
# Run the bench, parse the BENCH stats line, and append one record to
# autoresearch/log.jsonl. Prints the parsed stats to stdout.
#
# Usage: autoresearch/run_iteration.sh "<short summary of the change>" [label]
#   label defaults to "trial"; use "baseline" or "revert" for special cases.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/autoresearch/log.jsonl"
BENCH_LOG_DIR="$ROOT/autoresearch/bench_logs"
mkdir -p "$BENCH_LOG_DIR"

summary="${1:-}"
label="${2:-trial}"

GODOT="${GODOT:-godot4}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
    if [ -x "$HOME/bin/godot4" ]; then
        GODOT="$HOME/bin/godot4"
    else
        echo "godot binary not found; set GODOT or add godot4 to PATH" >&2
        exit 2
    fi
fi

# Iteration number = (lines in log) + 1.
iter=1
if [ -f "$LOG" ]; then
    iter=$(( $(wc -l < "$LOG") + 1 ))
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
bench_log="$BENCH_LOG_DIR/$(printf "%04d" "$iter").log"

set +e
# NOTE: do NOT pass --headless. Godot's headless mode uses a dummy
# rasterizer and bypasses the GPU, which would make fps_avg measure
# CPU-only work and miss the renderer entirely. We need a real display.
"$GODOT" --path "$ROOT" -- --bench >"$bench_log" 2>&1
status=$?
set -e

# Surface BENCH lines for the agent to read.
grep -E "^BENCH" "$bench_log" || true

# Parse stats line. Missing values become null.
stats_line="$(grep -E "^BENCH stats" "$bench_log" | tail -1 || true)"
chunks_line="$(grep -E "^BENCH chunks" "$bench_log" | tail -1 || true)"

extract() {
    # extract <key> <line> -> value or empty
    local k="$1" line="$2"
    echo "$line" | grep -oE "${k}=[0-9.]+" | head -1 | cut -d= -f2
}

avg_ms=$(extract avg_ms "$stats_line")
p50_ms=$(extract p50_ms "$stats_line")
p95_ms=$(extract p95_ms "$stats_line")
p99_ms=$(extract p99_ms "$stats_line")
max_ms=$(extract max_ms "$stats_line")
fps_avg=$(extract fps_avg "$stats_line")
loaded=$(extract loaded "$chunks_line")

# JSON-escape summary.
esc_summary=$(printf '%s' "$summary" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

n_or_null() { [ -n "$1" ] && echo "$1" || echo "null"; }

cat >>"$LOG" <<EOF
{"iter": $iter, "ts": "$ts", "label": "$label", "status": $status, "fps_avg": $(n_or_null "$fps_avg"), "avg_ms": $(n_or_null "$avg_ms"), "p50_ms": $(n_or_null "$p50_ms"), "p95_ms": $(n_or_null "$p95_ms"), "p99_ms": $(n_or_null "$p99_ms"), "max_ms": $(n_or_null "$max_ms"), "loaded": $(n_or_null "$loaded"), "bench_log": "autoresearch/bench_logs/$(basename "$bench_log")", "summary": $esc_summary}
EOF

echo
echo "iter=$iter status=$status fps_avg=${fps_avg:-NA} avg_ms=${avg_ms:-NA} p99_ms=${p99_ms:-NA}"
echo "log: $LOG"
echo "bench: $bench_log"

exit $status
