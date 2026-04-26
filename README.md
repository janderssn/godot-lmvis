# godot-lmvis

Real-terrain rendering foundation for a skiing/snowboarding game set in Åre, Sweden. Uses 1-meter resolution heightmap data from Lantmäteriet (Swedish mapping authority), streamed as chunks into Godot 4 with seamless cross-chunk meshing and slope/elevation-based shading.

The current build is a **terrain-only foundation** — orbit/fly camera over the Åreskutan summit. Player physics, tricks, and game systems are planned on top of it.

## Project Layout

```
.
├── project.godot              # Godot 4 project
├── scenes/
│   └── main.tscn             # Foundation scene (orbit + fly cam over Åreskutan)
├── src/
│   ├── main.gd               # Wires terrain loader + camera, focuses on Toppstugan
│   ├── terrain_camera.gd     # Orbit / fly camera with mouse-look in fly mode
│   ├── terrain_chunk.gd      # Per-chunk heightmap → ArrayMesh + collision
│   └── terrain_chunk_loader.gd  # Streaming, halo loading, cross-chunk sampling
├── scripts/                   # Python pipeline: heights, optional ortofoto, optional XYZ map tiles
├── docs/
│   ├── TERRAIN_DATA.md       # Heightmap chunk format + dataset manifest
│   ├── LANTMATERIET_SETUP.md # Geotorget account + STAC API setup
│   └── CHEATSHEET.md         # Common command reference
├── terrain_data/              # Generated heightmap data (gitignored, except manifests)
└── setup.sh                   # Environment sanity check
```

## Prerequisites

- **Godot 4.3+** ([godotengine.org](https://godotengine.org))
- **Python 3.10+** with pip (only needed to (re)generate terrain)
- **Lantmäteriet Geotorget account** with access to *Markhöjdmodell Nedladdning* (free, [register here](https://geotorget.lantmateriet.se))

## Quick Start

```bash
# 1. Install Python deps for the terrain pipeline
pip install -r scripts/requirements.txt

# 2. Set Lantmäteriet credentials
export LANTMATERIET_USERNAME="your_email@example.com"
export LANTMATERIET_PASSWORD="your_password"

# 3. Verify environment
./setup.sh

# 4. Download + convert terrain (central Åre, ~200–400 MB)
python scripts/quick_download.py central --process

# 5. Open project.godot in Godot and press F5
```

### Optional: photo-textured terrain

Near-tier chunks can render with real satellite imagery instead of the procedural grass/rock blend, by populating `terrain_data/ortho/` with a 256×256 PNG per heightmap chunk. Two routes:

#### Route A — XYZ map tiles (no extra auth, recommended)

`scripts/maptiles_to_chunks.py` pulls Web Mercator tiles from any XYZ provider, reprojects them to SWEREF99 TM, and writes one PNG per heightmap chunk:

```bash
python scripts/maptiles_to_chunks.py \
    --heights terrain_data/raw_height \
    --output  terrain_data/ortho \
    --zoom    16              # ~1 m/px at 63°N; 17 ≈ 0.5 m/px, 18 ≈ 0.25 m/px
```

Default source is **ESRI World Imagery** (the QGIS satellite default — free for development/non-commercial use, requires a "Imagery © Esri, Maxar, Earthstar Geographics" attribution somewhere visible in your final game UI). Override with `--url '<template with {z}/{x}/{y}>'` for other providers. Most providers' ToS restrict commercial use without an API key — check before shipping.

Mercator tiles cache under `terrain_data/maptile_cache/`, so re-runs at a different zoom only fetch the new resolution.

#### Route B — Lantmäteriet Ortofoto

Lantmäteriet ships an Ortofoto product on the same Geotorget account (same credentials as the heightmap). It's CC BY-licensed and matches the heightmap's tile grid exactly. Order *Ortofoto Nedladdning* on Geotorget first (see `docs/LANTMATERIET_SETUP.md`), then:

```bash
python scripts/download_ortofoto.py --list-collections      # find the right collection ID
python scripts/download_ortofoto.py \
    --collection orto-are-2024 \
    --bbox 13.0 63.32 13.2 63.44 \
    --output terrain_data/raw_ortho
python scripts/convert_ortofoto.py --batch \
    --input terrain_data/raw_ortho \
    --output terrain_data/ortho \
    --texture-size 256
```

#### How the textures get used

The `TerrainLoader` node's `ortho_directory` (default `res://terrain_data/ortho`) tells the chunk loader where to look. When a chunk has a matching PNG, `_resolve_material` swaps in a per-chunk `ShaderMaterial` with the texture bound; otherwise it falls back to the procedural slope/elevation shader. **Only near-tier chunks get textures** — far + horizon stay procedural to keep memory in check.

See `docs/LANTMATERIET_SETUP.md` for credential details, `docs/TERRAIN_DATA.md` for the chunk format, and `docs/CHEATSHEET.md` for download/convert commands.

## Controls

| Action | Key |
|---|---|
| Toggle orbit ↔ fly | `Tab` |
| Orbit / strafe | `A` `D` |
| Zoom / move forward·back | `W` `S` |
| Raise camera / fly up | `Space` |
| Lower camera / fly down | `Shift` |
| Fly boost | `Ctrl` |
| Fly look | Mouse (click to capture, `Esc` to release) |

## How the Terrain Renders

The rendering pipeline is engineered around the awkward shape of Lantmäteriet tiles (2500 m × 2500 m, 1 m resolution, zero-padded at edges):

1. **Chunking** — each tile is split into 256×256 overlapping chunks (`scripts/convert_terrain.py`). The right/bottom edge chunks of a tile are zero-padded where source data runs out.
2. **Streaming** — `terrain_chunk_loader.gd` keeps a spatial index of all chunks, finds the ones near the camera focus, and runs a two-phase load: heightmaps first (so neighbors are available), meshes second.
3. **Valid-extent meshing** — each chunk scans its heightmap for zero-padded rows/columns, then meshes only up to the first column with real data, plus one extra vertex queried from the adjacent tile via `loader.sample_height_int()`. That makes adjacent tiles meet seamlessly even when their boundaries are 205 units apart instead of the expected 255.
4. **Cross-chunk normals** — vertex normals come from heightmap central differences. Boundary normals query neighbor chunks through the loader, so chunks on either side of a seam compute the same normal at the shared world position.
5. **Indexed mesh** — `ArrayMesh` with packed vertex/normal/index arrays (instead of `SurfaceTool`) for fast per-chunk generation and ~4× fewer vertices.
6. **Per-frame budgets** — `max_data_loads_per_frame` and `max_mesh_gens_per_frame` (both `@export`) cap streaming work to keep flycam motion smooth; bulk mode loads everything at scene start.

The shader (`terrain_chunk.gd`, inline) blends grass → tundra → rock → cliff based on world-space elevation and slope (computed in the vertex shader from `MODEL_MATRIX` so camera tilt doesn't change the shading).

## Coordinate System

- **Real world** — SWEREF 99 TM (EPSG:3006), 1 m per pixel.
- **Game world** — Godot Y-up, 1 unit = 1 m. World X = (easting − dataset origin), world Z = (max_northing − northing) so +Z corresponds to south.
- `terrain_chunk_loader.sweref_to_local(easting, northing)` maps real coordinates into the game world. The Åreskutan summit / Toppstugan is hardcoded in `main.gd`.

## License

Game code: MIT. Terrain data: © Lantmäteriet, redistributed under their open data terms (see [Lantmäteriet open data](https://www.lantmateriet.se/en/geodata/geodata-products/open-data/)).
