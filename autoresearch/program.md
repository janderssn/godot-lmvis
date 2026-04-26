# Autoresearch — Terrain Rendering Optimization

You are an autonomous research agent in the spirit of [karpathy/autoresearch].
Goal: **maximize `fps_avg` of the godot-lmvis terrain bench**, ideally
sustained 30–60+ FPS, without visibly degrading terrain quality.

## The loop (one iteration ≈ 5 minutes)

Each time you wake up:

1. Read **state**:
   - `autoresearch/log.jsonl` — every prior trial, newest at bottom.
   - `autoresearch/best.txt` — current best `fps_avg` and snapshot name.
   - Skim `autoresearch/program.md` (this file) for the technique backlog.
2. Decide the **next experiment**. One change at a time. Pick from the
   backlog below or invent something better, and write a one-line
   hypothesis (e.g. "halve far-tier vertex stride → -50% verts, ≥+10% fps").
3. **Snapshot** the current `src/`:
   `autoresearch/snapshot.sh pre-iter-<n>`
4. **Edit** files under `src/` (and only `src/`). You may add new files
   such as `src/shaders/*.gdshader`. Do not touch `terrain_data/`,
   `scripts/`, `scenes/`, or anything else.
5. **Run the bench** with a short, descriptive summary of the change:
   `autoresearch/run_iteration.sh "halve far-tier vertex stride"`
   This appends one record to `log.jsonl` with `fps_avg`, `avg_ms`,
   `p99_ms`, and the bench output snippet.
6. **Decide kept-or-reverted** by reading the freshly-appended record:
   - If `fps_avg` ≥ best × (1 - 0.01) **and** `p99_ms` not >20% worse
     than best's p99 → **keep**. If it's a new best, run
     `autoresearch/snapshot.sh kept-iter-<n>-best` and update
     `autoresearch/best.txt` (one line: `<fps_avg> <snapshot_name>`).
   - Else → **revert**: `autoresearch/revert.sh <best snapshot>` and
     mark the trial `"kept": false` by appending a follow-up record with
     `label="revert"`.
7. **Stop the iteration** (return control to /loop). Do not start
   another change in the same turn.

## Hard rules

- **Never** edit files outside `src/`.
- **Never** delete `autoresearch/snapshots/` or `log.jsonl`.
- **Never** modify `scripts/bench.sh` or `src/main.gd`'s bench code —
  the metric must stay comparable across trials.
- One conceptual change per iteration. If a change touches 3 files
  toward the same hypothesis, that's fine; mixing two unrelated
  hypotheses is not.
- If the bench fails to launch (`status != 0`), revert immediately and
  log the failure. Do not "fix-forward" by stacking changes.
- If you find a Godot import error caused by your edit, fix syntactically
  in-place is allowed *within the same iteration* before re-running bench
  once. After that, revert.

## Technique backlog (pick whatever looks promising)

Drawn from the literature and Godot specifics — not a rigid checklist.

### Mesh & LOD
- **Per-tier vertex stride:** today every chunk meshes at full 1 m
  resolution. Reduce stride for far chunks (e.g. step 2/4/8). See
  `terrain_chunk.gd` mesh generation.
- **CDLOD-style continuous LOD** (Strugar 2009): single shader-based
  morph between LOD levels keyed on camera distance. Avoids popping.
- **GeoMipMapping** (de Boer 2000): per-chunk discrete LOD with skirt
  stitching. Easier than CDLOD; works well with the existing chunk grid.
- **Geometry clipmaps** (Hoppe/Asirvatham 2005): nested rings, very few
  buffers. Bigger refactor but the streaming model fits.
- **Skirts vs. stitching:** cheaper than seam fixups when LODs differ.
- **Index buffer reuse:** if all chunks share grid topology, build the
  index buffer once and reuse across chunks (saves RAM + upload).
- **Strip vs. list:** triangle strips with primitive restart can cut
  index bandwidth ~30%.

### Culling & draw calls
- **Distance-based hide:** hard-cull beyond horizon ring; horizon
  arrays already exist — verify they're not double-rendered.
- **MultiMesh / MeshInstance3D batching** for far tiers if topology is
  identical — one draw call vs. many.
- **Custom AABBs** so the renderer doesn't bound-check oversized meshes.
- **Disable shadow casting** on far/horizon chunks.

### Materials & shaders
- **Combine grass/rock blend into a single fragment branch** instead of
  two passes. Inspect `terrain_chunk.gd` material setup.
- **Triplanar off** for far tiers; cheap UV mapping is fine at distance.
- **Drop normal map sampling** beyond N meters.
- **Static lighting / unshaded for horizon ring** — it's already mostly
  silhouette.
- **Compress textures to BC1/BC3** (importer settings via `.import` —
  but those live outside `src/`, so skip unless we move logic into code).

### Streaming & memory
- **Async chunk meshing on a worker thread** (`WorkerThreadPool`).
- **Pre-warm:** bench shows `loaded N / N` — if not all loaded by warmup
  end, increase warmup or trigger eager load.
- **Mesh pooling:** reuse `ArrayMesh` instances on chunk eviction
  (Godot 4 Vulkan is slow at destroying mesh buffers on the main thread).

### Quick wins to try first (low risk, often big)
1. Cull/skip horizon tier if not visible from current camera frustum.
2. Reduce far-chunk vertex stride 2× then 4×.
3. Disable shadow casting on far + horizon tiers.
4. Move chunk meshing off the main thread.

## Metric

`fps_avg` from the line:

```
BENCH stats avg_ms=… min_ms=… p50_ms=… p95_ms=… p99_ms=… max_ms=… fps_avg=…
```

Higher is better. Target: ≥ 30 FPS sustained, stretch ≥ 60 FPS.

## On exploration

Don't get stuck refining one technique. After ~5 trials in the same
direction with no gain, switch to a different category in the backlog.
Note dead ends in your iteration summaries so future-you doesn't redo
them.

[karpathy/autoresearch]: https://github.com/karpathy/autoresearch
