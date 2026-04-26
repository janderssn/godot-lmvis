#!/usr/bin/env bash
# Snapshot src/ into autoresearch/snapshots/<NNNN>-<tag>.tar.zst
# Usage: autoresearch/snapshot.sh <tag>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAP_DIR="$ROOT/autoresearch/snapshots"
mkdir -p "$SNAP_DIR"

tag="${1:-untagged}"
# Sanitize tag
tag="$(echo "$tag" | tr -c 'A-Za-z0-9._-' '-' | cut -c1-60)"

# Next sequence number
n=$(ls "$SNAP_DIR" 2>/dev/null | grep -Eo '^[0-9]+' | sort -n | tail -1 || true)
n=$((${n:-0} + 1))
name=$(printf "%04d-%s.tar.zst" "$n" "$tag")
out="$SNAP_DIR/$name"

if command -v zstd >/dev/null 2>&1; then
    tar -C "$ROOT" -cf - src | zstd -q -19 -o "$out"
else
    out="${out%.zst}"
    tar -C "$ROOT" -cf "$out" src
fi

echo "$name"
