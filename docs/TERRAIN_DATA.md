# Lantmäteriet Terrain Data Guide

This document explains how to download real terrain data from Lantmäteriet (Swedish mapping agency) and use it in Godot.

## Credentials

```
Username: your_email@example.com
Password: your_password
```

Register at: https://geotorget.lantmateriet.se

## 1. Download Terrain via STAC API

Lantmäteriet provides terrain data through a STAC (SpatioTemporal Asset Catalog) API.

### API Endpoint
```
https://api.lantmateriet.se/stac-hojd/v1
```

### Authentication
HTTP Basic Auth with your Geotorget credentials.

### Download Command

```bash
cd /home/joel/dev/are-steep-game

# Option 1: Using environment variables
export LANTMATERIET_USERNAME="your_email@example.com"
export LANTMATERIET_PASSWORD="your_password"
python3 scripts/download_terrain.py --bbox 13.0 63.35 13.15 63.45

# Option 2: Inline credentials
LANTMATERIET_USERNAME="your_email@example.com" LANTMATERIET_PASSWORD="your_password" \
    python3 scripts/download_terrain.py --bbox 13.0 63.35 13.15 63.45
```

### Bounding Box Format

The `--bbox` parameter uses WGS84 coordinates (lon/lat):
```
--bbox <lon_min> <lat_min> <lon_max> <lat_max>
```

**Example regions:**
```bash
# Åre ski area
--bbox 13.0 63.35 13.15 63.45

# Åre central (tighter area)
--bbox 13.05 63.38 13.12 63.42

# Custom area - use Google Maps to find coordinates
# Right-click in Google Maps to get lat/lon
```

### What Gets Downloaded

- **File format:** GeoTIFF (.tif)
- **Resolution:** 1 meter per pixel
- **Tile size:** 2500×2500 pixels (2.5km × 2.5km)
- **Coordinate system:** SWEREF99 TM (EPSG:3006)
- **Height values:** Float32, meters above sea level

Files are saved to: `terrain_data/raw/`

## 2. Convert to Godot Format

The GeoTIFF files need to be converted to a format Godot can efficiently load.

### Conversion Command

```bash
python3 scripts/convert_terrain.py terrain_data/raw \
    --output terrain_data/raw_height \
    --format chunks \
    --chunk-format raw \
    --batch
```

### Parameters

- `--format chunks`: Split into smaller chunks for LOD
- `--chunk-format raw`: Use float32 for best precision (recommended)
- `--chunk-format png`: 16-bit PNG (has precision issues)
- `--chunk-format r16`: 16-bit raw (has precision issues)
- `--chunk-size 256`: Size of each chunk (default: 256)

### Output Structure

```
terrain_data/raw_height/
├── 70350_4025_25/
│   ├── chunk_0000_0000.raw    # 256×256 float32 values (262KB each)
│   ├── chunk_0000_0255.raw
│   ├── ...
│   └── chunks_manifest.json   # Metadata with world coordinates
├── 70350_4050_25/
│   └── ...
└── (26 tile directories, 100 chunks each = 2600 total chunks)
```

### Manifest Format

Each `chunks_manifest.json` contains:
```json
{
  "original_file": "terrain_data/raw/70350_4025_25.tif",
  "chunk_size": 256,
  "overlap": 1,
  "total_chunks": 100,
  "world_offset_x": 7500,
  "world_offset_z": 10000,
  "chunks": [
    {
      "file": "chunk_0000_0000.raw",
      "world_x": 7500,
      "world_z": 10000,
      "size": 256
    }
  ]
}
```

## 3. Godot Implementation

### Project Structure

```
are-steep-game/
├── scenes/
│   └── main.tscn              # Main scene with terrain loader
├── src/
│   ├── terrain_chunk_loader.gd  # Loads all chunks
│   ├── terrain_chunk.gd         # Generates mesh from height data
│   └── terrain_camera.gd        # Orbit / fly camera
├── scripts/
│   ├── download_terrain.py      # STAC API client
│   └── convert_terrain.py       # GeoTIFF converter
└── terrain_data/
    ├── raw/                     # Downloaded GeoTIFFs
    └── raw_height/              # Converted chunks
```

### Terrain Chunk Loader

```gdscript
# src/terrain_chunk_loader.gd
extends Node3D

@export var height_directory: String = "res://terrain_data/raw_height"
@export var chunk_size: int = 256
@export var height_scale: float = 1.0  # Raw files are already in meters

var loaded_chunks: Dictionary = {}
var all_chunks: Array = []

func _ready():
    _load_all_manifests()
    _load_all_chunks()

func _load_all_manifests():
    var dir = DirAccess.open(height_directory)
    dir.list_dir_begin()
    var folder = dir.get_next()
    while folder != "":
        if dir.current_is_dir() and not folder.begins_with("."):
            var manifest_path = height_directory.path_join(folder).path_join("chunks_manifest.json")
            if FileAccess.file_exists(manifest_path):
                _load_manifest(manifest_path, folder)
        folder = dir.get_next()

func _load_manifest(manifest_path: String, tile_name: String):
    var file = FileAccess.open(manifest_path, FileAccess.READ)
    var json = JSON.new()
    if json.parse(file.get_as_text()) == OK:
        for chunk in json.data.get("chunks", []):
            chunk["tile_folder"] = tile_name
            all_chunks.append(chunk)

func _load_all_chunks():
    for chunk_data in all_chunks:
        var coord = Vector2i(chunk_data.world_x / (chunk_size - 1), chunk_data.world_z / (chunk_size - 1))
        _load_chunk_from_data(coord, chunk_data)

func _load_chunk_from_data(coord: Vector2i, chunk_data: Dictionary):
    var chunk_path = height_directory.path_join(chunk_data.tile_folder).path_join(chunk_data.file)
    var chunk = preload("res://src/terrain_chunk.gd").new()
    chunk.setup(coord.x, coord.y, chunk_path, height_scale)
    chunk.position = Vector3(coord.x * chunk_size, 0, coord.y * chunk_size)
    add_child(chunk)
    chunk.generate()
    loaded_chunks[coord] = chunk

func get_height_at_position(pos: Vector3) -> float:
    var coord = Vector2i(int(pos.x / chunk_size), int(pos.z / chunk_size))
    if not loaded_chunks.has(coord):
        return 0.0
    var chunk = loaded_chunks[coord]
    var local_x = pos.x - (coord.x * chunk_size)
    var local_z = pos.z - (coord.y * chunk_size)
    return chunk.get_height_at(local_x, local_z)
```

### Terrain Chunk

```gdscript
# src/terrain_chunk.gd
extends StaticBody3D

var heightmap_data: PackedFloat32Array
var data_size: int = 256
var height_scale: float = 1.0
var lod_step: int = 2

func setup(x: int, z: int, chunk_path: String, scale: float = 1.0):
    name = "Chunk_%d_%d" % [x, z]
    height_scale = scale
    
    var file = FileAccess.open(chunk_path, FileAccess.READ)
    if file == null:
        return
    
    var raw = file.get_buffer(data_size * data_size * 4)
    file.close()
    
    heightmap_data = PackedFloat32Array()
    heightmap_data.resize(data_size * data_size)
    for i in range(data_size * data_size):
        heightmap_data[i] = raw.decode_float(i * 4) * height_scale

func generate():
    if heightmap_data.is_empty():
        return
    
    var st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    
    for z in range(0, data_size - lod_step, lod_step):
        for x in range(0, data_size - lod_step, lod_step):
            var h00 = _h(x, z)
            var h10 = _h(x + lod_step, z)
            var h01 = _h(x, z + lod_step)
            var h11 = _h(x + lod_step, z + lod_step)
            
            var p00 = Vector3(x, h00, z)
            var p10 = Vector3(x + lod_step, h10, z)
            var p01 = Vector3(x, h01, z + lod_step)
            var p11 = Vector3(x + lod_step, h11, z + lod_step)
            
            # Triangle 1
            st.add_vertex(p00)
            st.add_vertex(p10)
            st.add_vertex(p01)
            
            # Triangle 2
            st.add_vertex(p10)
            st.add_vertex(p11)
            st.add_vertex(p01)
    
    st.generate_normals()
    
    var mesh = st.commit()
    var mi = MeshInstance3D.new()
    mi.mesh = mesh
    add_child(mi)

func _h(x: int, z: int) -> float:
    x = clamp(x, 0, data_size - 1)
    z = clamp(z, 0, data_size - 1)
    return heightmap_data[z * data_size + x]

func get_height_at(local_x: float, local_z: float) -> float:
    var x0 = int(local_x)
    var z0 = int(local_z)
    var x1 = min(x0 + 1, data_size - 1)
    var z1 = min(z0 + 1, data_size - 1)
    
    x0 = clamp(x0, 0, data_size - 1)
    z0 = clamp(z0, 0, data_size - 1)
    
    var h00 = _h(x0, z0)
    var h10 = _h(x1, z0)
    var h01 = _h(x0, z1)
    var h11 = _h(x1, z1)
    
    var fx = local_x - x0
    var fz = local_z - z0
    
    var h0 = h00 * (1 - fx) + h10 * fx
    var h1 = h01 * (1 - fx) + h11 * fx
    
    return h0 * (1 - fz) + h1 * fz
```

## 4. Coordinate Systems

### SWEREF99 TM (Lantmäteriet native)

- **EPSG:** 3006
- **Units:** Meters
- **Origin:** 500000 E, 0 N
- **Central meridian:** 15°E
- **Format:** Easting (X), Northing (Y)

### WGS84 (GPS/Google Maps)

- **EPSG:** 4326
- **Units:** Degrees
- **Format:** Longitude, Latitude

### Godot World Coordinates

- **X axis:** Easting (meters from origin)
- **Z axis:** Northing (meters from origin)
- **Y axis:** Height (meters above sea level)

### Conversion Formula (Approximate)

For central Sweden:
```python
# SWEREF99 to WGS84 (approximate)
lat = northing / 111320
lon = 15 + (easting - 500000) / (111320 * cos(radians(lat)))

# WGS84 to SWEREF99 (approximate)
easting = 500000 + (lon - 15) * 111320 * cos(radians(lat))
northing = lat * 111320
```

For accurate conversion, use `pyproj` library:
```python
from pyproj import Transformer
transformer = Transformer.from_crs("EPSG:3006", "EPSG:4326", always_xy=True)
lon, lat = transformer.transform(easting, northing)
```

## 5. Finding Coordinates for Your Area

### Using Google Maps

1. Go to https://maps.google.com
2. Navigate to your area of interest
3. Right-click and select coordinates
4. Format: 63.400000, 13.089000 (lat, lon)

### Using Lantmäteriet's STAC Browser

1. Go to https://api.lantmateriet.se/stac-hojd/v1 (requires auth)
2. Browse collections: `mhm-XX_X` where XX is the region code
3. Each collection has a bounding box

### Region Collection Codes

The collection `mhm-70_4` covers Åre:
- BBox: lon 12.95-15.0, lat 63.12-64.03

Search with:
```bash
python3 scripts/download_terrain.py --bbox 12.95 63.12 15.0 64.03
```

## 6. File Sizes & Performance

### Typical Download

- **26 tiles** (2.5km × 2.5km each)
- **Total area:** 12.5km × 7.5km
- **GeoTIFF size:** ~10-12 MB per tile
- **Total download:** ~260 MB

### After Conversion

- **2600 chunks** (256×256 each)
- **Raw file size:** 262 KB per chunk
- **Total raw data:** ~680 MB

### Godot Performance

- **Load time:** 30-60 seconds for 2600 chunks
- **Memory:** ~1-2 GB for terrain mesh
- **GPU:** Depends on mesh complexity with LOD

## 7. Troubleshooting

### "Authentication failed"

- Verify credentials at https://geotorget.lantmateriet.se
- Check that you've ordered "Markhöjdmodell Nedladdning" access
- Wait up to 24 hours after ordering

### "No tiles found"

- Bounding box might be outside available data
- Try a larger bbox
- Check collection availability in your area

### Terrain has stepping/precision issues

- Use `--chunk-format raw` (not png or r16)
- Raw float32 preserves exact meter heights

### Chunks don't align

- The converter calculates global coordinates automatically
- Each tile's `world_offset_x` and `world_offset_z` position it correctly

### Game shows blue screen

- Run `godot4 --editor --headless --quit` to import files first
- Check console for "Loaded X chunks" message
- Verify `chunks_manifest.json` files exist

## 8. Quick Reference

```bash
# Download terrain
LANTMATERIET_USERNAME="your_email@example.com" \
LANTMATERIET_PASSWORD="your_password" \
python3 scripts/download_terrain.py --bbox 13.0 63.35 13.15 63.45

# Convert to Godot format
python3 scripts/convert_terrain.py terrain_data/raw \
    --output terrain_data/raw_height \
    --format chunks \
    --chunk-format raw \
    --batch

# Import in Godot
godot4 --editor --headless --quit

# Run game
godot4
```

## 9. API Documentation

### STAC API Endpoints

```
GET  /                           # Root catalog
GET  /collections                # List all collections
GET  /collections/{id}           # Collection details
GET  /collections/{id}/items     # Items in collection
GET  /items/{id}                 # Single item
POST /search                     # Search items
```

### Search Parameters

```json
{
  "bbox": [lon_min, lat_min, lon_max, lat_max],
  "collections": ["mhm-70_4"],
  "limit": 100,
  "intersects": {
    "type": "Point",
    "coordinates": [lon, lat]
  }
}
```

### Item Response

```json
{
  "id": "703_40_0025",
  "geometry": { ... },
  "bbox": [lon_min, lat_min, lon_max, lat_max],
  "assets": {
    "data": {
      "href": "https://dl1.lantmateriet.se/hojd/data/...",
      "type": "image/tiff"
    }
  }
}
```
