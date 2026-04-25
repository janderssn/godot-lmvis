# Åre Steep - Quick Start Guide

Get from zero to skiing in 5 minutes.

## Prerequisites

- Python 3.10+
- Godot 4.3+
- Lantmäteriet Geotorget account (free)

## 1. Install Dependencies

```bash
cd are-steep-game
pip install -r scripts/requirements.txt
```

## 2. Get Lantmäteriet Access

1. Register at https://geotorget.lantmateriet.se
2. Order access to **"Markhöjdmodell Nedladdning"** (free, instant approval)
3. Set environment variables:

```bash
export LANTMATERIET_USERNAME="your_email@example.com"
export LANTMATERIET_PASSWORD="your_password"
```

**Tip**: Add these to your `~/.bashrc` or `~/.zshrc` to persist them.

See `docs/LANTMATERIET_SETUP.md` for detailed instructions with screenshots.

## 3. Verify Setup

```bash
./setup.sh
```

Should show all green checkmarks ✅

## 4. Download Terrain

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

## 5. Open in Godot

1. Launch Godot 4.3+
2. Import the `project.godot` file
3. Open `scenes/main.tscn` which is already configured as the foundation terrain scene

## 6. Run!

Press F5 or the play button in Godot.

**Controls:**
- `Tab` - Toggle orbit / fly mode
- `WASD` or Arrow keys - Orbit adjust / fly move
- `Space` / `Shift` - Raise or lower the camera
- `Ctrl` - Fly boost
- Mouse - Look around in fly mode

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "LANTMATERIET_USERNAME not set" | Run `export LANTMATERIET_USERNAME="your_email"` |
| "401 Unauthorized" | Wrong username/password, or access not yet approved |
| "No terrain data" | Run the download script first |
| Player falls through ground | Make sure GroundCheck RayCast3D is enabled |
| Terrain not loading | Check TerrainLoader chunk_directory path |

## Full Documentation

- `README.md` - Complete project documentation
- `docs/LANTMATERIET_SETUP.md` - Detailed API setup with screenshots
- `docs/CHEATSHEET.md` - Common commands reference

## Next Steps

1. Add your own 3D models for the skier
2. Customize the physics in `skier_controller.gd`
3. Add more terrain areas
4. Implement tricks and scoring

Happy skiing! 🎿
