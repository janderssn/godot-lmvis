#!/usr/bin/env bash
# Restore src/ from a snapshot.
# Usage: autoresearch/revert.sh <snapshot-name-or-"best">
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAP_DIR="$ROOT/autoresearch/snapshots"
BEST_FILE="$ROOT/autoresearch/best.txt"

target="${1:?usage: revert.sh <snapshot-name|best>}"

if [ "$target" = "best" ]; then
    if [ ! -f "$BEST_FILE" ]; then
        echo "no best.txt yet — cannot revert to best" >&2
        exit 2
    fi
    target=$(awk '{print $2}' "$BEST_FILE")
fi

src_path="$SNAP_DIR/$target"
[ -f "$src_path" ] || { echo "snapshot not found: $src_path" >&2; exit 2; }

# Wipe and restore.
rm -rf "$ROOT/src"
case "$src_path" in
    *.tar.zst) zstd -dc "$src_path" | tar -C "$ROOT" -xf - ;;
    *.tar)     tar -C "$ROOT" -xf "$src_path" ;;
    *) echo "unknown snapshot format: $src_path" >&2; exit 2 ;;
esac

echo "reverted src/ from $target"
