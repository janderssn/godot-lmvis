#!/usr/bin/env python3
"""
Fetch XYZ map tiles (Web Mercator) and reproject them to match the SWEREF99 TM
heightmap chunks produced by convert_terrain.py.

Each heightmap chunk's PNG is rendered by:
  1. Computing its SWEREF99 TM bbox.
  2. Reprojecting bbox corners to WGS84 → Web Mercator.
  3. Pulling the XYZ tiles that cover the Mercator bbox at --zoom.
  4. Reprojecting from EPSG:3857 to EPSG:3006, cropped + resampled to 256×256.

Tiles are cached on disk so a re-run is incremental.

Default XYZ source is ESRI World Imagery — fine for development/non-commercial.
For other providers (OSM, Mapbox, etc.), pass --url. Respect each provider's
attribution + ToS.

Usage:
    python scripts/maptiles_to_chunks.py \\
        --heights terrain_data/raw_height \\
        --output  terrain_data/ortho \\
        --zoom    16
"""

import argparse
import io
import json
import math
import time
from pathlib import Path

import numpy as np
import rasterio
import requests
from PIL import Image
from pyproj import Transformer
from rasterio.io import MemoryFile
from rasterio.transform import from_bounds
from rasterio.warp import Resampling, reproject


DEFAULT_URL = (
    "https://server.arcgisonline.com/ArcGIS/rest/services/"
    "World_Imagery/MapServer/tile/{z}/{y}/{x}"
)
DEFAULT_USER_AGENT = "godot-lmvis/0.1 (terrain texturing)"
TILE_PX = 256
CHUNK_PX = 256                 # output chunk PNG size
HEIGHT_CHUNK_SAMPLES = 256     # samples in heightmap chunk grid
HEIGHT_CHUNK_OVERLAP = 1


# --- Web Mercator math --------------------------------------------------------

def lonlat_to_tile(lon: float, lat: float, zoom: int):
    """Return (x_tile, y_tile, x_frac, y_frac) at integer zoom."""
    n = 2.0 ** zoom
    x = (lon + 180.0) / 360.0 * n
    lat_r = math.radians(lat)
    y = (1.0 - math.log(math.tan(lat_r) + 1.0 / math.cos(lat_r)) / math.pi) / 2.0 * n
    return x, y


def tile_to_mercator_bounds(xt: int, yt: int, zoom: int):
    """Return (xmin, ymin, xmax, ymax) of a tile in EPSG:3857."""
    n = 2.0 ** zoom
    half = 20037508.342789244
    xmin = xt / n * 2 * half - half
    xmax = (xt + 1) / n * 2 * half - half
    ymax = half - yt / n * 2 * half
    ymin = half - (yt + 1) / n * 2 * half
    return xmin, ymin, xmax, ymax


# --- Tile fetcher -------------------------------------------------------------

def fetch_tile(session, url_tmpl: str, z: int, x: int, y: int, cache: Path) -> Path:
    p = cache / str(z) / str(x) / f"{y}.png"
    if p.exists() and p.stat().st_size > 0:
        return p
    url = url_tmpl.format(z=z, x=x, y=y)
    p.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(3):
        try:
            r = session.get(url, timeout=20)
            r.raise_for_status()
            p.write_bytes(r.content)
            return p
        except Exception as e:
            if attempt == 2:
                print(f"  tile {z}/{x}/{y} failed after retries: {e}")
                return None
            time.sleep(0.5 * (attempt + 1))
    return None


# --- Mosaic + reproject for one chunk -----------------------------------------

class TileSource:
    def __init__(self, session, url_tmpl: str, zoom: int, cache: Path):
        self.session = session
        self.url_tmpl = url_tmpl
        self.zoom = zoom
        self.cache = cache

    def mosaic_for_mercator_bbox(self, mxmin, mymin, mxmax, mymax):
        """Return (np.ndarray HxWx3 uint8, transform) covering the bbox in EPSG:3857."""
        n = 2.0 ** self.zoom
        half = 20037508.342789244
        xt_min = int((mxmin + half) / (2 * half) * n)
        xt_max = int((mxmax + half) / (2 * half) * n)
        yt_min = int((half - mymax) / (2 * half) * n)
        yt_max = int((half - mymin) / (2 * half) * n)
        xt_min = max(0, xt_min)
        yt_min = max(0, yt_min)
        xt_max = max(xt_min, xt_max)
        yt_max = max(yt_min, yt_max)

        cols = xt_max - xt_min + 1
        rows = yt_max - yt_min + 1
        mosaic = np.zeros((rows * TILE_PX, cols * TILE_PX, 3), dtype=np.uint8)

        for ry, yt in enumerate(range(yt_min, yt_max + 1)):
            for cx, xt in enumerate(range(xt_min, xt_max + 1)):
                p = fetch_tile(self.session, self.url_tmpl, self.zoom, xt, yt, self.cache)
                if p is None:
                    continue
                img = Image.open(p).convert("RGB")
                if img.size != (TILE_PX, TILE_PX):
                    img = img.resize((TILE_PX, TILE_PX), Image.LANCZOS)
                mosaic[
                    ry * TILE_PX:(ry + 1) * TILE_PX,
                    cx * TILE_PX:(cx + 1) * TILE_PX,
                ] = np.asarray(img)

        # Mosaic geographic bounds
        gxmin, _, _, gymax = tile_to_mercator_bounds(xt_min, yt_min, self.zoom)
        _, gymin, gxmax, _ = tile_to_mercator_bounds(xt_max, yt_max, self.zoom)
        transform = from_bounds(gxmin, gymin, gxmax, gymax, mosaic.shape[1], mosaic.shape[0])
        return mosaic, transform


# --- Heightmap chunk traversal ------------------------------------------------

def render_chunk(
    src: TileSource,
    sweref_to_lonlat: Transformer,
    lonlat_to_mercator: Transformer,
    sweref_origin_x: float,
    sweref_origin_y: float,
    sweref_size: float,
    out_path: Path,
    overwrite: bool,
):
    if out_path.exists() and not overwrite:
        return False

    # Chunk bbox in SWEREF99 TM
    sxmin = sweref_origin_x
    symin = sweref_origin_y
    sxmax = sweref_origin_x + sweref_size
    symax = sweref_origin_y + sweref_size

    # Sample bbox corners + midpoints in lon/lat to be safe near projection bends
    pts_e = [sxmin, sxmin, sxmax, sxmax, (sxmin + sxmax) / 2]
    pts_n = [symin, symax, symin, symax, (symin + symax) / 2]
    lons, lats = sweref_to_lonlat.transform(pts_e, pts_n)
    mxs, mys = lonlat_to_mercator.transform(lons, lats)
    pad_m = 5.0  # small pad to avoid edge bleed
    mxmin = min(mxs) - pad_m
    mxmax = max(mxs) + pad_m
    mymin = min(mys) - pad_m
    mymax = max(mys) + pad_m

    mosaic, src_transform = src.mosaic_for_mercator_bbox(mxmin, mymin, mxmax, mymax)
    if mosaic.size == 0 or mosaic.max() == 0:
        return False

    # Build source dataset in memory
    with MemoryFile() as memfile:
        with memfile.open(
            driver="GTiff",
            height=mosaic.shape[0],
            width=mosaic.shape[1],
            count=3,
            dtype="uint8",
            crs="EPSG:3857",
            transform=src_transform,
        ) as src_ds:
            for i in range(3):
                src_ds.write(mosaic[:, :, i], i + 1)

            dst_transform = from_bounds(sxmin, symin, sxmax, symax, CHUNK_PX, CHUNK_PX)
            dst = np.zeros((3, CHUNK_PX, CHUNK_PX), dtype=np.uint8)

            for i in range(3):
                reproject(
                    source=rasterio.band(src_ds, i + 1),
                    destination=dst[i],
                    src_transform=src_transform,
                    src_crs="EPSG:3857",
                    dst_transform=dst_transform,
                    dst_crs="EPSG:3006",
                    resampling=Resampling.lanczos,
                )

    out_img = np.transpose(dst, (1, 2, 0))
    # rasterio.from_bounds(west, south, east, north) puts pixel row 0 at the
    # north edge of the chunk in SWEREF — which is also where the chunk's
    # local Z=0 vertex sits, so UV.y=0 lines up with the top of the PNG.
    out_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out_img, mode="RGB").save(out_path, optimize=True)
    return True


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--heights", required=True, help="dir with per-tile heightmap chunk folders")
    p.add_argument("--output", required=True, help="output ortho dir (mirrors per-tile structure)")
    p.add_argument("--cache", default="terrain_data/maptile_cache")
    p.add_argument("--url", default=DEFAULT_URL,
                   help="XYZ URL with {z}{x}{y} placeholders (note ESRI uses {y} before {x})")
    p.add_argument("--zoom", type=int, default=16,
                   help="XYZ zoom level (16 ≈ 1m/px at 63°N, 17 ≈ 0.5m, 18 ≈ 0.25m)")
    p.add_argument("--user-agent", default=DEFAULT_USER_AGENT)
    p.add_argument("--overwrite", action="store_true")
    p.add_argument("--limit", type=int, help="cap chunks for a quick test")
    args = p.parse_args()

    heights = Path(args.heights)
    output = Path(args.output)
    cache = Path(args.cache)

    dataset_manifest = heights / "dataset_manifest.json"
    if not dataset_manifest.exists():
        p.error(f"no dataset_manifest.json in {heights}")

    ds = json.loads(dataset_manifest.read_text())
    origin_e = float(ds["origin_easting"])
    max_n = float(ds["max_northing"])
    chunk_size = int(ds.get("chunk_size", HEIGHT_CHUNK_SAMPLES))
    overlap = int(ds.get("chunk_overlap", HEIGHT_CHUNK_OVERLAP))
    chunk_step = chunk_size - overlap

    sweref_to_lonlat = Transformer.from_crs("EPSG:3006", "EPSG:4326", always_xy=True)
    lonlat_to_mercator = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True)

    session = requests.Session()
    session.headers["User-Agent"] = args.user_agent
    src = TileSource(session, args.url, args.zoom, cache)

    total = 0
    wrote = 0
    for tile_dir in sorted(heights.iterdir()):
        if not tile_dir.is_dir():
            continue
        chunks_manifest = tile_dir / "chunks_manifest.json"
        if not chunks_manifest.exists():
            continue
        cm = json.loads(chunks_manifest.read_text())
        parts = tile_dir.name.split("_")
        if len(parts) < 3:
            continue
        south_n = int(parts[0]) * 100
        west_e = int(parts[1]) * 100
        tile_size_m = int(parts[2]) * 100
        tile_top_n = south_n + tile_size_m

        out_tile_dir = output / tile_dir.name

        for chunk_meta in cm["chunks"]:
            stem = chunk_meta["file"].rsplit(".", 1)[0]
            row, col = stem.replace("chunk_", "").split("_")
            row = int(row)
            col = int(col)

            sweref_origin_x = west_e + col
            sweref_origin_y = (south_n + tile_size_m) - (row + chunk_step)

            out_path = out_tile_dir / f"{stem}.png"
            try:
                # Texture spans chunk_step (255 m) of ground — that's the
                # vertex-to-vertex distance on the chunk mesh (256 samples at
                # 1 m resolution = 255 m between sample 0 and sample 255).
                # Using chunk_size (256) here would inflate the texture by 1 m
                # and cause sub-pixel drift across every chunk seam.
                ok = render_chunk(
                    src,
                    sweref_to_lonlat,
                    lonlat_to_mercator,
                    sweref_origin_x,
                    sweref_origin_y,
                    chunk_step,
                    out_path,
                    args.overwrite,
                )
                if ok:
                    wrote += 1
            except Exception as e:
                print(f"  failed {tile_dir.name}/{stem}: {e}")
            total += 1
            if args.limit and total >= args.limit:
                print(f"reached --limit {args.limit}")
                _write_manifest(out_tile_dir, cm, args.zoom, args.url)
                print(f"done: {wrote}/{total} chunks rendered")
                return

        _write_manifest(out_tile_dir, cm, args.zoom, args.url)

    print(f"done: {wrote}/{total} chunks rendered")


def _write_manifest(out_tile_dir: Path, source_manifest: dict, zoom: int, url: str):
    if not out_tile_dir.exists():
        return
    manifest = {
        "source_url": url,
        "zoom": zoom,
        "chunk_size_samples": HEIGHT_CHUNK_SAMPLES,
        "overlap": HEIGHT_CHUNK_OVERLAP,
        "texture_size": CHUNK_PX,
        "chunks": [
            {"file": c["file"].rsplit(".", 1)[0] + ".png",
             "row": c.get("world_z", 0),
             "col": c.get("world_x", 0)}
            for c in source_manifest.get("chunks", [])
        ],
    }
    (out_tile_dir / "chunks_manifest.json").write_text(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
