# Åre Steep

A skiing and snowboarding game set in Åre, Sweden, using real 1-meter resolution terrain data from Lantmäteriet (the Swedish mapping authority).

Inspired by **Steep** (Ubisoft), this game features:
- Physics-based skiing and snowboarding
- Real Åre terrain with dynamic chunk loading
- Trick system with grabs, spins, and flips
- Race challenges and checkpoints

## Project Structure

```
are-steep-game/
├── project.godot          # Godot project configuration
├── QUICKSTART.md          # 5-minute quick start guide
├── README.md              # This file
├── setup.sh               # Environment setup checker
├── assets/                # Game assets (models, textures, sounds)
├── docs/                  # Documentation
│   ├── LANTMATERIET_SETUP.md  # Detailed API setup guide
│   └── CHEATSHEET.md      # Commands reference
├── scenes/                # Godot scene files
├── src/                   # GDScript source code
│   ├── main.gd           # Main game scene
│   ├── terrain_chunk.gd       # Individual terrain chunk
│   ├── terrain_chunk_loader.gd  # Dynamic terrain streaming
│   ├── skier_controller.gd  # Player physics controller
│   └── follow_camera.gd     # Third-person camera
├── scripts/               # Python pipeline scripts
│   ├── download_terrain.py  # STAC API client (HTTP Basic Auth)
│   ├── convert_terrain.py   # GeoTIFF → Godot converter
│   ├── quick_download.py    # One-command download helper
│   ├── setup.py            # Environment checker
│   └── requirements.txt     # Python dependencies
└── terrain_data/          # Downloaded and converted terrain data
    ├── raw/              # Original GeoTIFF files from STAC
    └── raw_height/       # Streamable float32 terrain chunks + dataset manifest
```

## Prerequisites

- **Godot 4.3+** (https://godotengine.org)
- **Python 3.10+** with pip
- **Lantmäteriet Geotorget account** with access to Markhöjdmodell (free)

## Quick Start

### 1. Clone/Download the Project

```bash
cd /path/to/are-steep-game
```

### 2. Install Python Dependencies

```bash
pip install -r scripts/requirements.txt
```

### 3. Get Lantmäteriet Access

1. Register at https://geotorget.lantmateriet.se
2. Order access to **"Markhöjdmodell Nedladdning"** (free)
3. Set environment variables with your credentials:

```bash
export LANTMATERIET_USERNAME="your_email@example.com"
export LANTMATERIET_PASSWORD="your_password"
```

See `docs/LANTMATERIET_SETUP.md` for detailed instructions.

### 4. Verify Setup

```bash
./setup.sh
```

Should show all green checkmarks ✅

### 5. Download Terrain Data

Quick option - just central Åre:
```bash
python scripts/quick_download.py central --process
```

This downloads ~200-400MB and converts it automatically.

Available areas:
- `central` - Central Åre, Kabinbanan (recommended for testing)
- `bjornen` - Björnen area
- `duved` - Duved area  
- `tegefjall` - Tegefjäll
- `full` - All of Åre ski area (~1-2GB)

### 6. Open in Godot

1. Launch Godot 4.3+
2. Click "Import" and select the `project.godot` file
3. Open the project

### 7. Open the Foundation Scene

`scenes/main.tscn` is included and set as the main scene. It loads the streamed Åre terrain, focuses the camera on the Åreskutan summit / Toppstugan area, and lets you switch between orbit and fly controls.

### 8. Run!

Press F5 or the play button in Godot.

## Controls

| Action | Keyboard | Gamepad |
|--------|----------|---------|
| Orbit / Strafe | A/D or ←/→ | Left Stick X |
| Zoom / Move Forward | W or ↑ | Left Stick Y- |
| Zoom Out / Move Back | S or ↓ | Left Stick Y+ |
| Raise Camera / Fly Up | Space | A/Cross |
| Lower Camera / Fly Down | Shift | RT/R2 |
| Toggle Orbit/Fly | Tab | - |
| Fly Boost | Ctrl | - |

## How It Works

### Terrain Data Pipeline

1. **Download**: Query the STAC API for tiles within a bounding box
2. **Convert**: GeoTIFF → 16-bit PNG chunks with metadata
3. **Stream**: Godot loads chunks dynamically based on player position
4. **Stream**: Godot loads terrain around the active camera focus

### Authentication

The Lantmäteriet STAC API uses **HTTP Basic Authentication** with your Geotorget username (email) and password. Credentials are passed via:
- Environment variables: `LANTMATERIET_USERNAME` and `LANTMATERIET_PASSWORD`
- Or command line: `--user` and `--pass` flags (not recommended)

### Physics

The skier controller uses a custom physics system:
- Gravity pulls down the slope (not just down)
- Edge control allows carving turns
- Air physics with limited steering
- Crash detection based on impact and angle

### Coordinate System

- **Real world**: SWEREF 99 TM (EPSG:3006)
- **Game world**: Godot Y-up, 1 unit = 1 meter
- **Åre center**: approximately E 377000, N 7035000

## Development Roadmap

- [x] Project structure and Godot setup
- [x] Terrain data pipeline (STAC API + convert)
- [x] Dynamic chunk loading system
- [x] Basic skiing physics controller
- [x] Third-person follow camera
- [ ] Trick system (grabs, spins, flips)
- [ ] Ragdoll physics for crashes
- [ ] Race gates and checkpoints
- [ ] Score system
- [ ] Multiplayer support
- [ ] Åre-specific landmarks (Kabinbanan, etc.)

## Manual Terrain Download

If you need more control:

```bash
# List available collections
python scripts/download_terrain.py --list-collections

# Download specific region
python scripts/download_terrain.py --region are_central --output terrain_data/raw

# Download with custom bounding box (SWEREF 99 TM coordinates)
python scripts/download_terrain.py --bbox 377000 7035000 379500 7037500 --output terrain_data/raw

# Dry run - see what would be downloaded
python scripts/download_terrain.py --region are_central --dry-run
```

## Convert Terrain

```bash
# Convert all downloaded tiles to chunks
python scripts/convert_terrain.py --batch \
  --input terrain_data/raw \
  --output terrain_data/raw_height \
  --format chunks \
  --chunk-format raw \
  --chunk-size 256

# Convert to single PNG (for small areas)
python scripts/convert_terrain.py \
  --input terrain_data/raw/mh-1m_xxx.tif \
  --output terrain_data/raw_height \
  --format png
```

## License

The terrain data is from Lantmäteriet and is available under their terms for valuable data (CC BY 4.0). See https://www.lantmateriet.se

The game code is released under MIT License.

## Troubleshooting

### "401 Unauthorized"
- Check your username and password
- Verify you have ordered access to Markhöjdmodell in Geotorget
- Ensure your account is verified (check email)

### "No chunks manifest found"
Make sure you've run the convert script and the `terrain_data/raw_height` folder contains `chunks_manifest.json`.

### Terrain not loading
- Check that the TerrainLoader's `chunk_directory` is set correctly
- Verify the path is `res://terrain_data/raw_height`
- Check Godot's Output panel (F12) for errors

### Player falls through terrain
- Make sure the player starts above the terrain
- Check that GroundCheck RayCast3D is enabled and pointing down
- Verify terrain chunks have collision shapes

### Download is slow
Tiles are 50-100MB each. This is normal. Tips:
- Start with `central` region (1-4 tiles)
- Use a wired connection
- Tiles are served from Sweden - international connections may be slower

## Credits

- Terrain data: © Lantmäteriet, Sweden
- Inspired by: Steep (Ubisoft Annecy)

## Documentation

- `QUICKSTART.md` - 5-minute setup guide
- `docs/LANTMATERIET_SETUP.md` - Detailed API setup with screenshots
- `docs/CHEATSHEET.md` - Command reference
