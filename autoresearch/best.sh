#!/usr/bin/env bash
# Print the current best (highest fps_avg) trial from log.jsonl, plus a
# short summary table. Reads/writes autoresearch/best.txt as
# "<fps_avg> <snapshot_name>".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/autoresearch/log.jsonl"
BEST_FILE="$ROOT/autoresearch/best.txt"

if [ ! -s "$LOG" ]; then
    echo "no log yet"
    exit 0
fi

python3 - "$LOG" "$BEST_FILE" <<'PY'
import json, sys, os
log_path, best_path = sys.argv[1], sys.argv[2]
trials = []
with open(log_path) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            trials.append(json.loads(line))
        except json.JSONDecodeError:
            pass

scored = [
    t for t in trials
    if t.get("fps_avg") is not None
    and t.get("status", 1) == 0
    and not t.get("label", "").startswith("invalid")
    and t.get("label") != "revert"
]
if not scored:
    print("no successful trials yet")
    sys.exit(0)

best = max(scored, key=lambda t: t["fps_avg"])
print(f"best: iter={best['iter']} fps_avg={best['fps_avg']} avg_ms={best.get('avg_ms')} p99_ms={best.get('p99_ms')} label={best['label']}")
print(f"  summary: {best.get('summary','')}")

print()
print(f"{'iter':>4}  {'label':<10}  {'fps':>6}  {'p99':>6}  summary")
for t in trials[-15:]:
    fps = t.get("fps_avg"); p99 = t.get("p99_ms")
    print(f"{t['iter']:>4}  {t['label'][:10]:<10}  {('%.1f' % fps) if fps is not None else '   NA':>6}  {('%.1f' % p99) if p99 is not None else '   NA':>6}  {t.get('summary','')[:80]}")
PY
