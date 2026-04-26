# Getting Lantmäteriet API Access - Step by Step

This guide walks you through accessing the 1-meter resolution terrain data for Åre using the STAC API with HTTP Basic Authentication.

## Overview

Lantmäteriet's **Markhöjdmodell Nedladdning** provides 1-meter resolution height data for all of Sweden. The API uses:
- **STAC (SpatioTemporal Asset Catalog)** for searching tiles
- **HTTP Basic Auth** with your Geotorget username/password
- **SWEREF 99 TM (EPSG:3006)** as the native coordinate system
- **GeoTIFF** format for the actual height data

## Step 1: Create a Geotorget Account

1. Go to https://geotorget.lantmateriet.se
2. Click **"Logga in"** (Login) in the top right
3. Click **"Skapa konto"** (Create account)
4. Fill in your details:
   - Email address (this will be your username)
   - Password (at least 8 characters)
   - Confirm password
   - Accept terms of service
5. Click **"Skaka konto"**
6. Check your email for a verification link
7. Click the verification link to activate your account

## Step 2: Request Access to Markhöjdmodell

1. Log in to Geotorget with your new account
2. Go to **"Produkter"** (Products) in the menu
3. Search for **"Markhöjdmodell"** or browse to:
   - Höjd- och djupdata → Markhöjdmodell Nedladdning
4. Click on **"Markhöjdmodell Nedladdning"**
5. Click the **"Beställ"** (Order) button
6. Fill in the order form:
   - **Användningsområde** (Use case): "Spelutveckling / Game development"
   - **Beskrivning**: "Utveckling av ett skidspel baserat på Åres verkliga terräng"
   - Check the box accepting the license terms (CC BY 4.0)
7. Submit the order

**Note**: Access is typically granted within minutes (automated for most users).

### Optional: Ortofoto (aerial color imagery)

For photo-textured terrain there are two routes (see README "Optional: photo-textured terrain"):

1. **XYZ map tiles** via `scripts/maptiles_to_chunks.py` — no Lantmäteriet auth needed at all, default ESRI World Imagery, just an attribution requirement.
2. **Lantmäteriet Ortofoto** — same Geotorget account, separate product order. Order **Ortofoto Nedladdning** from the Produkter page, same HTTP Basic Auth as the heightmap, different STAC endpoint:

   - Heightmap: `https://api.lantmateriet.se/stac-hojd/v1`
   - Ortofoto:  `https://api.lantmateriet.se/stac-bild/v1`

   `scripts/download_ortofoto.py` + `scripts/convert_ortofoto.py` reuse the same `LANTMATERIET_USERNAME` / `LANTMATERIET_PASSWORD` you set up below. Listing collections doesn't need extra access; downloading the actual imagery returns 403 until *Ortofoto Nedladdning* is ordered and granted.

## Step 3: Configure Your Environment

The API uses **HTTP Basic Authentication** with your Geotorget username (email) and password.

### Option A: Environment Variables (Recommended)

Add to your shell profile (`~/.bashrc`, `~/.zshrc`, or `~/.profile`):

```bash
export LANTMATERIET_USERNAME="your_email@example.com"
export LANTMATERIET_PASSWORD="your_password"
```

Then reload:
```bash
source ~/.bashrc  # or ~/.zshrc
```

### Option B: .env File

Create a `.env` file in the project root:

```bash
cd /home/joel/dev/are-steep-game
cat > .env << 'EOF'
LANTMATERIET_USERNAME=your_email@example.com
LANTMATERIET_PASSWORD=your_password
EOF
```

The Python scripts will automatically load this file if `python-dotenv` is installed:

```bash
pip install python-dotenv
```

### Option C: Direct Command Line

```bash
cd scripts
python download_terrain.py --region are_central \
  --user "your_email@example.com" \
  --pass "your_password"
```

**Warning**: This exposes your password in shell history. Prefer environment variables.

## Step 4: Test Your Setup

Run a dry-run to verify everything works:

```bash
cd /home/joel/dev/are-steep-game/scripts
python download_terrain.py --region are_central --dry-run
```

Expected output:
```
Using region: are_central
Bounding box (SWEREF 99 TM): (374500, 7032500, 379500, 7037500)

Searching for tiles...
Found 4 tile(s)

Tiles that would be downloaded:
  - mh-1m_374500_7032500_379500_7037500
    Asset: data
```

If you see "Authentication failed" error:
1. Check your credentials: `echo $LANTMATERIET_USERNAME`
2. Verify you have access to Markhöjdmodell (check Geotorget "Mina beställningar")
3. Ensure your account is verified (check email)

## Step 5: Explore the API

### List Available Collections

```bash
python download_terrain.py --list-collections
```

You'll see something like:
```
ID: markhojdmodell-grid-1m
Title: Markhöjdmodell Grid 1m
Description: Nationell höjddata med 1 meters upplösning...
```

### Browse Interactively

You can explore the STAC catalog visually:

1. Go to https://radiantearth.github.io/stac-browser/
2. Enter the catalog URL: `https://api.lantmateriet.se/stac-hojd/v1/`
3. Authenticate with your username/password when prompted
4. Browse collections and preview tiles

Or use the OpenAPI docs: `https://api.lantmateriet.se/stac-hojd/v1/api.html`

## Step 6: Download Terrain Data

Download tiles for the Åre region:

```bash
python scripts/download_terrain.py --region are_central --output ../terrain_data/raw
```

This will download GeoTIFF files (~50-100 MB per tile) to `terrain_data/raw/`.

### Available Regions

| Region | Description | Approximate Size | BBox (SWEREF 99 TM) |
|--------|-------------|------------------|---------------------|
| `are_central` | Kabinbanan, central village | 1-4 tiles | 374500,7032500,379500,7037500 |
| `are_bjornen` | Björnen area | 1-2 tiles | 376000,7030000,378500,7032500 |
| `are_duved` | Duved area | 1-2 tiles | 372000,7037500,374500,7040000 |
| `are_tegefjall` | Tegefjäll | 1-2 tiles | 375000,7027500,377500,7030000 |
| `are_full` | All of Åre ski area | 10-20 tiles | 372000,7025000,380000,7045000 |

**Recommendation**: Start with `are_central` for testing (~100-400 MB).

### Using Custom Bounding Boxes

You can specify exact coordinates in SWEREF 99 TM:

```bash
python scripts/download_terrain.py \
  --bbox 377000 7035000 379500 7037500 \
  --output terrain_data/raw
```

Or in WGS84 (lon/lat), but SWEREF 99 TM is recommended for pixel-perfect alignment:

```bash
python scripts/download_terrain.py \
  --bbox 12.95 63.35 13.15 63.45 \
  --output terrain_data/raw
```

## Step 7: Convert for Godot

Once downloaded, convert the GeoTIFFs to Godot-compatible format:

```bash
python scripts/convert_terrain.py --batch \
  --input terrain_data/raw \
  --output terrain_data/raw_height \
  --format chunks \
  --chunk-format raw \
  --chunk-size 256
```

This creates:
- `terrain_data/raw_height/TILE_NAME/chunk_XXXX_YYYY.raw` (256×256 float32 height chunks)
- `terrain_data/raw_height/TILE_NAME/chunks_manifest.json` (chunk metadata)
- `terrain_data/raw_height/dataset_manifest.json` (dataset origin + peak metadata)

Processing takes 1-2 minutes per tile.

## Quick Start (One Command)

Use the helper script to download and convert in one step:

```bash
python scripts/quick_download.py central --process
```

This downloads the central Åre region and automatically converts it.

## Understanding the Data

Each downloaded tile:
- **Coverage**: 2.5 km × 2.5 km
- **Resolution**: 1 meter per pixel
- **Size**: 2500 × 2500 pixels = 6.25 million height samples
- **Format**: GeoTIFF, LZW compressed
- **Height range**: Typically 300-1400m for Åre
- **Coordinate system**: SWEREF 99 TM (EPSG:3006)

### Data Structure

```
terrain_data/
├── raw/                          # Original GeoTIFFs (don't commit)
│   ├── mh-1m_374500_7032500_379500_7037500.tif
│   └── ...
└── processed/                    # Godot-ready chunks
    └── mh-1m_374500_7032500_379500_7037500/
        ├── chunk_0000_0000.png
        ├── chunk_0000_0256.png
        ├── ...
        └── chunks_manifest.json
```

## Troubleshooting

### "401 Unauthorized"
Your credentials are incorrect or access hasn't been granted:
```bash
# Verify credentials
echo "Username: $LANTMATERIET_USERNAME"

# Check if password is set (won't show value)
if [ -z "$LANTMATERIET_PASSWORD" ]; then echo "Password not set"; else echo "Password is set"; fi
```

### "403 Forbidden"
Your Geotorget account doesn't have access to Markhöjdmodell yet:
1. Check "Mina beställningar" (My orders) in Geotorget
2. Ensure the order status is "Beviljad" (Approved)
3. Wait 5-10 minutes after approval for API access to propagate

### "No tiles found"
The bounding box might be outside the data coverage or too small:
- Use the predefined regions first
- Try a larger bounding box
- Check that coordinates are in the correct order (min_x, min_y, max_x, max_y)

### Download is very slow
The tiles are large (50-100 MB each). This is normal. Tips:
- Download just one tile first to test
- Use a wired connection if possible
- Tiles are served from Sweden - international connections may be slower

### Conversion fails with "No module named 'rasterio'"
Install the Python dependencies:
```bash
pip install -r scripts/requirements.txt
```

## Using cURL Directly

If you prefer using cURL instead of the Python script:

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

## Next Steps

Once you have terrain data:
1. Open the project in Godot 4.3+
2. Create the Main scene (see README.md)
3. Run the game!

## Reference

- **STAC Specification**: https://stacspec.org
- **Lantmäteriet API Portal**: https://api.lantmateriet.se
- **Interactive API Docs**: https://api.lantmateriet.se/stac-hojd/v1/api.html
- **STAC Browser**: https://radiantearth.github.io/stac-browser/

## License

The terrain data is from Lantmäteriet and is available under CC BY 4.0. 
See https://www.lantmateriet.se for full terms.
