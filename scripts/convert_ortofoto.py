#!/usr/bin/env python3
"""
Slice ortofoto GeoTIFFs into 256-pixel chunks aligned with the heightmap
chunks produced by convert_terrain.py.

Uses no credentials — this stage just chunks already-downloaded GeoTIFFs.
For the download stage and Geotorget account setup, see
docs/LANTMATERIET_SETUP.md.

Output layout mirrors terrain_data/raw_height — one folder per source tile,
filled with chunk_RRRR_CCCC.png + chunks_manifest.json. Each PNG is the
256×256 m ground area of the corresponding heightmap chunk, downsampled (if
needed) to a fixed texture size so RAM doesn't explode at high source
resolutions.

Each chunk filename's RRRR_CCCC matches the heightmap chunk in tile-local
sample coordinates, where the sample grid is the heightmap's 1m grid (so
a 0.5m ortofoto gets 2× more pixels per chunk than the heightmap before
downsampling).

Usage:
    python scripts/convert_ortofoto.py --batch \\
        --input terrain_data/raw_ortho \\
        --output terrain_data/ortho \\
        --texture-size 256
"""

import argparse
import json
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image


HEIGHT_CHUNK_SIZE = 256          # samples per chunk in heightmap's 1m grid
HEIGHT_CHUNK_OVERLAP = 1          # samples shared with neighbor chunk


def slice_tile(
    tif_path: Path,
    output_dir: Path,
    texture_size: int = 256,
    overwrite: bool = False,
) -> int:
    """Slice one GeoTIFF into chunk PNGs. Returns number of chunks written."""
    with rasterio.open(tif_path) as src:
        bands = src.count
        if bands < 3:
            print(f"  skipping {tif_path.name}: only {bands} band(s), need RGB")
            return 0

        # Read first 3 bands as RGB
        red = src.read(1)
        green = src.read(2)
        blue = src.read(3)
        rgb = np.dstack([red, green, blue])

        # Source pixel size in meters
        px_size = abs(src.transform.a)
        if px_size <= 0:
            print(f"  skipping {tif_path.name}: invalid transform")
            return 0

        # How many source pixels cover one heightmap-grid sample
        scale = 1.0 / px_size
        chunk_pixels = int(round(HEIGHT_CHUNK_SIZE * scale))
        step_pixels = int(round((HEIGHT_CHUNK_SIZE - HEIGHT_CHUNK_OVERLAP) * scale))
        h, w = rgb.shape[:2]

        output_dir.mkdir(parents=True, exist_ok=True)
        chunks_meta = []
        wrote = 0

        for row_idx, row_px in enumerate(range(0, h - HEIGHT_CHUNK_OVERLAP, step_pixels)):
            for col_idx, col_px in enumerate(range(0, w - HEIGHT_CHUNK_OVERLAP, step_pixels)):
                end_row = min(row_px + chunk_pixels, h)
                end_col = min(col_px + chunk_pixels, w)
                tile = rgb[row_px:end_row, col_px:end_col]

                # Pad to full chunk_pixels (matches heightmap zero-padding)
                if tile.shape[0] < chunk_pixels or tile.shape[1] < chunk_pixels:
                    padded = np.zeros((chunk_pixels, chunk_pixels, 3), dtype=tile.dtype)
                    padded[: tile.shape[0], : tile.shape[1]] = tile
                    tile = padded

                # Downsample to texture_size if source is finer than target
                if chunk_pixels != texture_size:
                    img = Image.fromarray(tile.astype(np.uint8), mode="RGB")
                    img = img.resize((texture_size, texture_size), Image.LANCZOS)
                else:
                    img = Image.fromarray(tile.astype(np.uint8), mode="RGB")

                # Use heightmap-grid sample coords in the filename
                row_sample = row_idx * (HEIGHT_CHUNK_SIZE - HEIGHT_CHUNK_OVERLAP)
                col_sample = col_idx * (HEIGHT_CHUNK_SIZE - HEIGHT_CHUNK_OVERLAP)
                name = f"chunk_{row_sample:04d}_{col_sample:04d}.png"
                out_path = output_dir / name
                if out_path.exists() and not overwrite:
                    chunks_meta.append({"file": name, "row": row_sample, "col": col_sample})
                    continue

                img.save(out_path, optimize=True)
                chunks_meta.append({"file": name, "row": row_sample, "col": col_sample})
                wrote += 1

        manifest = {
            "source": tif_path.name,
            "source_resolution_m": px_size,
            "texture_size": texture_size,
            "chunk_size_samples": HEIGHT_CHUNK_SIZE,
            "overlap": HEIGHT_CHUNK_OVERLAP,
            "chunks": chunks_meta,
        }
        with open(output_dir / "chunks_manifest.json", "w") as f:
            json.dump(manifest, f, indent=2)
        return wrote


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--batch", action="store_true", help="Process all .tif in --input")
    p.add_argument("--input", required=True, help="Input dir (--batch) or file")
    p.add_argument("--output", required=True, help="Output base dir (per-tile subdirs created)")
    p.add_argument("--texture-size", type=int, default=256)
    p.add_argument("--overwrite", action="store_true")
    args = p.parse_args()

    input_path = Path(args.input)
    output_base = Path(args.output)

    tifs = []
    if args.batch:
        if not input_path.is_dir():
            p.error(f"--batch needs a directory; got {input_path}")
        tifs = sorted(input_path.glob("*.tif")) + sorted(input_path.glob("*.tiff"))
    else:
        tifs = [input_path]

    if not tifs:
        print(f"No GeoTIFFs found in {input_path}")
        return

    total = 0
    for tif in tifs:
        # Output subdir uses the source filename stem so it matches whatever
        # naming convention the heightmap pipeline used (typically the tile id).
        sub = output_base / tif.stem
        print(f"{tif.name} -> {sub}")
        total += slice_tile(tif, sub, texture_size=args.texture_size, overwrite=args.overwrite)
    print(f"Wrote {total} chunk image(s)")


if __name__ == "__main__":
    main()
