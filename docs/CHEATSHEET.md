# godot-lmvis - Command Cheat Sheet

## Setup & Environment

```bash
# Check everything is ready
./setup.sh

# Or use Python directly
python scripts/setup.py

# Set credentials (add to ~/.bashrc or ~/.zshrc for persistence)
export LANTMATERIET_USERNAME="your_email@example.com"
export LANTMATERIET_PASSWORD="your_password"

# Or create .env file
cat > .env << 'EOF'
LANTMATERIET_USERNAME=your_email@example.com
LANTMATERIET_PASSWORD=your_password
EOF
```

## Terrain Data

### Quick Download
```bash
# Central Åre only (recommended for testing)
python scripts/quick_download.py central --process

# All available areas
python scripts/quick_download.py full --process

# Other areas
python scripts/quick_download.py bjornen --process
python scripts/quick_download.py duved --process
python scripts/quick_download.py tegefjall --process
```

### Manual Download
```bash
# Download only
python scripts/download_terrain.py --region are_central --output terrain_data/raw

# With custom bounding box (SWEREF 99 TM coordinates)
python scripts/download_terrain.py --bbox 377000 7035000 379500 7037500 --output terrain_data/raw

# Dry run (see what would be downloaded)
python scripts/download_terrain.py --region are_central --dry-run

# List available collections
python scripts/download_terrain.py --list-collections

# With explicit credentials (not recommended - use env vars)
python scripts/download_terrain.py --region are_central --user email --pass password
```

### Convert Terrain
```bash
# Convert all downloaded tiles
python scripts/convert_terrain.py --batch \
  --input terrain_data/raw \
  --output terrain_data/raw_height \
  --format chunks \
  --chunk-format raw \
  --chunk-size 256

# Convert single file to chunks
python scripts/convert_terrain.py \
  terrain_data/raw/mh-1m_xxx.tif \
  --output terrain_data/raw_height \
  --format chunks

# Convert to single PNG (for small areas)
python scripts/convert_terrain.py \
  terrain_data/raw/mh-1m_xxx.tif \
  --output terrain_data/raw_height \
  --format png

# Convert to raw .r16 format
python scripts/convert_terrain.py \
  terrain_data/raw/mh-1m_xxx.tif \
  --output terrain_data/raw_height \
  --format r16
```

### Photo textures from XYZ map tiles
```bash
# Render one PNG per heightmap chunk from satellite tiles (no auth needed).
# Default source: ESRI World Imagery — attribution required for non-commercial use.
python scripts/maptiles_to_chunks.py \
  --heights terrain_data/raw_height \
  --output  terrain_data/ortho \
  --zoom    16                # 16 ≈ 1 m/px, 17 ≈ 0.5 m/px, 18 ≈ 0.25 m/px

# Other XYZ providers
python scripts/maptiles_to_chunks.py \
  --heights terrain_data/raw_height \
  --output  terrain_data/ortho \
  --url     'https://tile.openstreetmap.org/{z}/{x}/{y}.png'

# Test with a few chunks first
python scripts/maptiles_to_chunks.py --heights terrain_data/raw_height \
  --output terrain_data/ortho --zoom 16 --limit 12
```

### Photo textures from Lantmäteriet Ortofoto (alternative)
```bash
# Discover collection IDs for the current Lantmäteriet ortofoto STAC
python scripts/download_ortofoto.py --list-collections

# Download (Geotorget needs a separate "Ortofoto Nedladdning" order on top of Markhöjdmodell)
python scripts/download_ortofoto.py \
  --collection orto-are-2024 \
  --bbox 13.0 63.32 13.2 63.44 \
  --output terrain_data/raw_ortho

# Slice each GeoTIFF into chunk-aligned PNGs
python scripts/convert_ortofoto.py --batch \
  --input terrain_data/raw_ortho \
  --output terrain_data/ortho \
  --texture-size 256
```

## Godot Development

See `README.md` for the canonical project layout. The terrain-relevant
scripts and their key tunables live here:

**Terrain Loader (`src/terrain_chunk_loader.gd`):**
```gdscript
height_directory = "res://terrain_data/raw_height"
load_radius = 6                    # chunks around the focus that get a mesh
unload_radius = 8                  # chunks to keep before freeing
chunk_size = 256                   # samples per chunk side
overlap = 1                        # within-tile shared edge sample
visual_lod_step = 4                # mesh sampling step (visual)
collision_lod_step = 8             # mesh sampling step (collision)
max_data_loads_per_frame = 16      # per-frame heightmap load budget
max_mesh_gens_per_frame = 4        # per-frame mesh build budget
```

**Camera (`src/terrain_camera.gd`):**
```gdscript
orbit_radius = 850.0       # m, orbit distance
orbit_height = 260.0       # m, orbit height above focus
orbit_speed = 0.14         # rad/s automatic spin
fly_speed = 220.0          # m/s
fly_boost_multiplier = 3.0
mouse_sensitivity = 0.003
```

## Git Commands

```bash
# Clone repo (when you put it on GitHub)
git clone https://github.com/yourusername/godot-lmvis.git

# Never commit terrain data
echo "terrain_data/raw/*.tif" >> .gitignore
echo "terrain_data/raw_height/**/*.raw" >> .gitignore

# Commit only code and manifests
git add src/ scripts/ scenes/ docs/ README.md
git commit -m "Add terrain system"
```

## Useful Godot Shortcuts

| Key | Action |
|-----|--------|
| F5 | Play scene |
| F6 | Play current scene |
| F7 | Pause |
| F8 | Stop |
| F1 | 3D viewport |
| Ctrl+S | Save |
| Ctrl+Shift+S | Save all |
| Space | Search help |

## Debug Commands

In-game (when running):
- Hold F12 - Show debug info

In Godot editor:
- Remote scene tree (while running) - Debug > Remote Scene Tree
- Profiler - Debug > Profiler
- Monitor - Debug > Monitor

## Python Environment

```bash
# Create virtual environment (recommended)
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r scripts/requirements.txt

# Update dependencies
pip install --upgrade -r scripts/requirements.txt
```

## Common Issues

### "LANTMATERIET_USERNAME not set"
```bash
# Set credentials
export LANTMATERIET_USERNAME="your_email@example.com"
export LANTMATERIET_PASSWORD="your_password"

# Or use .env file
echo "LANTMATERIET_USERNAME=your_email@example.com" > .env
echo "LANTMATERIET_PASSWORD=your_password" >> .env
```

### "401 Unauthorized"
- Wrong username or password
- Account doesn't have Markhöjdmodell access yet
- Check "Mina beställningar" in Geotorget to verify approval

### "No module named 'rasterio'"
```bash
pip install -r scripts/requirements.txt
```

### Terrain chunks not loading
1. Check `chunk_directory` path is correct
2. Verify `chunks_manifest.json` exists
3. Check Godot output for errors (F12)

### Player falls through ground
1. Ensure GroundCheck RayCast3D is enabled
2. Check collision layers (Terrain = layer 1)
3. Verify terrain chunks have collision shapes

## Performance Tips

1. **Reduce chunk size** - Try 128 instead of 256 for lower-end systems
2. **Lower load radius** - Set to 2 instead of 3
3. **Simplify physics** - Reduce physics steps in Project Settings
4. **Use LOD** - Implement mesh LOD for distant chunks
5. **Occlusion culling** - Enable in Project Settings > Rendering

## Coordinates Reference

**Åre Key Locations (SWEREF 99 TM):**

| Location | Easting (X) | Northing (Z) |
|----------|-------------|--------------|
| Åre Torg | 377000 | 7035000 |
| Kabinbanan | 377200 | 7035200 |
| Björnen | 376500 | 7032000 |
| Duved | 373500 | 7038000 |
| Tegefjäll | 375500 | 7028000 |
| Åreskutan summit | 378000 | 7034000 |

**Coordinate conversion:**
- Real world: SWEREF 99 TM (EPSG:3006)
- Game world: Godot Y-up, 1 unit = 1 meter
- Z is negated in Godot (North = -Z)

## cURL Examples

If you prefer using cURL directly:

```bash
# Set credentials
USER="your_email@example.com"
PASS="your_password"

# List collections
curl -u "$USER:$PASS" \
  https://api.lantmateriet.se/stac-hojd/v1/collections

# Search for tiles (WGS84 coordinates)
curl -u "$USER:$PASS" -G \
  "https://api.lantmateriet.se/stac-hojd/v1/search" \
  --data-urlencode "bbox=13.0,63.3,13.2,63.5" \
  --data-urlencode "limit=100"

# Download a tile (replace URL with actual href from search results)
curl -u "$USER:$PASS" -o tile.tif \
  "https://api.lantmateriet.se/.../tile.tif"
```

## STAC API Resources

- **API Base URL**: https://api.lantmateriet.se/stac-hojd/v1/
- **Interactive Docs**: https://api.lantmateriet.se/stac-hojd/v1/api.html
- **STAC Browser**: https://radiantearth.github.io/stac-browser/
- **STAC Spec**: https://stacspec.org
