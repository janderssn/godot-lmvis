# Convert GeoTIFF heightmaps to Godot-compatible formats
# Supports: 16-bit PNG, .r16 raw files, and optimized chunks for LOD

import numpy as np
from PIL import Image
import rasterio
from rasterio.transform import from_origin
from pathlib import Path
import argparse
from typing import Tuple, Optional
import struct
import json


class GeoTIFFConverter:
    """
    Converts Lantmäteriet GeoTIFF heightmaps to formats usable by Godot.
    
    The 1m resolution tiles are 2500x2500 pixels (2.5km x 2.5km).
    For Godot, we need to:
    1. Normalize/scale height values for the game world
    2. Split into smaller chunks for efficient LOD
    3. Export as 16-bit PNG or raw .r16 format
    """
    
    def __init__(self, input_path: Path):
        self.input_path = input_path
        self.dataset = None
        self.data = None
        self.metadata = {}
        
    def load(self) -> "GeoTIFFConverter":
        """Load the GeoTIFF file."""
        self.dataset = rasterio.open(self.input_path)
        self.data = self.dataset.read(1)  # Read first band
        
        # Store metadata
        self.metadata = {
            "width": self.dataset.width,
            "height": self.dataset.height,
            "crs": str(self.dataset.crs),
            "bounds": self.dataset.bounds,
            "transform": list(self.dataset.transform),
            "resolution": self.dataset.res,
            "min_elevation": float(np.min(self.data[self.data > self.dataset.nodata])),
            "max_elevation": float(np.max(self.data[self.data > self.dataset.nodata])),
            "nodata": self.dataset.nodata
        }
        
        print(f"Loaded {self.input_path.name}")
        print(f"  Size: {self.metadata['width']}x{self.metadata['height']}")
        print(f"  Elevation range: {self.metadata['min_elevation']:.1f} - {self.metadata['max_elevation']:.1f}m")
        
        return self
    
    def get_normalized_heightmap(
        self,
        min_height: Optional[float] = None,
        max_height: Optional[float] = None
    ) -> np.ndarray:
        """
        Normalize height data to 16-bit range (0-65535).
        
        This preserves the full precision of the 1m resolution data
        while making it compatible with Godot's heightmap systems.
        """
        # Handle nodata values
        valid_mask = self.data > self.dataset.nodata if self.dataset.nodata else self.data > 0
        heights = self.data.copy().astype(np.float32)
        
        # Set nodata to minimum height
        if self.dataset.nodata:
            heights[heights <= self.dataset.nodata] = np.min(heights[valid_mask])
        
        # Determine height range
        if min_height is None:
            min_height = np.min(heights)
        if max_height is None:
            max_height = np.max(heights)
        
        # Normalize to 0-65535 range
        range_m = max_height - min_height
        if range_m > 0:
            normalized = ((heights - min_height) / range_m * 65535).astype(np.uint16)
        else:
            normalized = np.zeros_like(heights, dtype=np.uint16)
        
        self.metadata["normalized_min"] = min_height
        self.metadata["normalized_max"] = max_height
        self.metadata["height_scale"] = range_m / 65535.0
        
        return normalized
    
    def export_png(
        self,
        output_path: Path,
        min_height: Optional[float] = None,
        max_height: Optional[float] = None
    ) -> Path:
        """
        Export as 16-bit grayscale PNG.
        
        Godot's HeightMapShape3D can use 16-bit PNG directly.
        """
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        normalized = self.get_normalized_heightmap(min_height, max_height)
        
        # Create 16-bit grayscale image
        image = Image.fromarray(normalized, mode='I;16')
        image.save(output_path, compress_level=6)
        
        # Save metadata alongside
        meta_path = output_path.with_suffix('.json')
        with open(meta_path, 'w') as f:
            json.dump(self.metadata, f, indent=2)
        
        print(f"Exported PNG: {output_path}")
        return output_path
    
    def export_r16(
        self,
        output_path: Path,
        min_height: Optional[float] = None,
        max_height: Optional[float] = None
    ) -> Path:
        """
        Export as raw .r16 file (16-bit little-endian).
        
        This is the native format for Godot's RAW heightmap import.
        """
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        normalized = self.get_normalized_heightmap(min_height, max_height)
        
        # Write as little-endian uint16
        with open(output_path, 'wb') as f:
            # Flatten in row-major order
            flat_data = normalized.flatten()
            f.write(struct.pack('<' + 'H' * len(flat_data), *flat_data))
        
        # Save metadata alongside
        meta_path = output_path.with_suffix('.json')
        with open(meta_path, 'w') as f:
            json.dump(self.metadata, f, indent=2)
        
        print(f"Exported R16: {output_path}")
        return output_path
    
    def export_chunks(
        self,
        output_dir: Path,
        chunk_size: int = 256,
        overlap: int = 1,
        format: str = "png",
        world_offset_x: int = 0,
        world_offset_z: int = 0
    ) -> list[Path]:
        """
        Split the heightmap into smaller chunks for LOD streaming.
        
        Args:
            output_dir: Directory to save chunks
            chunk_size: Size of each chunk in pixels
            overlap: Overlap between chunks (for seamless stitching)
            format: 'png', 'r16', or 'raw' (float32)
            world_offset_x: Global X offset for this tile's chunks
            world_offset_z: Global Z offset for this tile's chunks
            
        Returns:
            List of exported chunk paths
        """
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        
        h, w = self.data.shape
        
        # For raw format, use original float32 data, not normalized
        if format == "raw":
            heights = self.data.copy().astype(np.float32)
            # Handle nodata
            if self.dataset.nodata:
                valid_mask = heights > self.dataset.nodata
                min_valid = np.min(heights[valid_mask])
                heights[heights <= self.dataset.nodata] = min_valid
        
        normalized = self.get_normalized_heightmap()
        
        chunks = []
        chunk_metadata = {
            "original_file": str(self.input_path),
            "chunk_size": chunk_size,
            "overlap": overlap,
            "total_chunks": 0,
            "world_offset_x": world_offset_x,
            "world_offset_z": world_offset_z,
            "chunks": []
        }
        
        # Calculate chunk positions with overlap
        step = chunk_size - overlap
        
        for row in range(0, h - overlap, step):
            for col in range(0, w - overlap, step):
                # Extract chunk
                end_row = min(row + chunk_size, h)
                end_col = min(col + chunk_size, w)
                
                # Global coordinates
                global_x = col + world_offset_x
                global_z = row + world_offset_z
                
                # Export chunk
                chunk_name = f"chunk_{row:04d}_{col:04d}"
                
                if format == "png":
                    chunk = normalized[row:end_row, col:end_col]
                    if chunk.shape[0] < chunk_size or chunk.shape[1] < chunk_size:
                        padded = np.zeros((chunk_size, chunk_size), dtype=np.uint16)
                        padded[:chunk.shape[0], :chunk.shape[1]] = chunk
                        chunk = padded
                    chunk_path = output_dir / f"{chunk_name}.png"
                    image = Image.fromarray(chunk, mode='I;16')
                    image.save(chunk_path, compress_level=6)
                elif format == "r16":
                    chunk = normalized[row:end_row, col:end_col]
                    if chunk.shape[0] < chunk_size or chunk.shape[1] < chunk_size:
                        padded = np.zeros((chunk_size, chunk_size), dtype=np.uint16)
                        padded[:chunk.shape[0], :chunk.shape[1]] = chunk
                        chunk = padded
                    chunk_path = output_dir / f"{chunk_name}.r16"
                    with open(chunk_path, 'wb') as f:
                        flat_data = chunk.flatten()
                        f.write(struct.pack('<' + 'H' * len(flat_data), *flat_data))
                else:  # raw (float32)
                    chunk = heights[row:end_row, col:end_col]
                    if chunk.shape[0] < chunk_size or chunk.shape[1] < chunk_size:
                        padded = np.zeros((chunk_size, chunk_size), dtype=np.float32)
                        padded[:chunk.shape[0], :chunk.shape[1]] = chunk
                        chunk = padded
                    chunk_path = output_dir / f"{chunk_name}.raw"
                    chunk.tofile(chunk_path)
                
                chunks.append(chunk_path)
                
                # Record chunk metadata with global coordinates
                chunk_metadata["chunks"].append({
                    "file": chunk_path.name,
                    "world_x": global_x,
                    "world_z": global_z,
                    "size": chunk_size
                })
        
        chunk_metadata["total_chunks"] = len(chunks)
        
        # Save chunk manifest
        manifest_path = output_dir / "chunks_manifest.json"
        with open(manifest_path, 'w') as f:
            json.dump(chunk_metadata, f, indent=2)
        
        print(f"Exported {len(chunks)} chunks to {output_dir}")
        return chunks
    
    def close(self):
        """Close the dataset."""
        if self.dataset:
            self.dataset.close()


def discover_dataset_bounds(tiff_files: list[Path]) -> tuple[int, int, int, int]:
    """Return the dataset bounds in projected meters."""
    min_x = float("inf")
    min_y = float("inf")
    max_x = float("-inf")
    max_y = float("-inf")

    for tiff_path in tiff_files:
        with rasterio.open(tiff_path) as src:
            bounds = src.bounds
            min_x = min(min_x, bounds.left)
            min_y = min(min_y, bounds.bottom)
            max_x = max(max_x, bounds.right)
            max_y = max(max_y, bounds.top)

    return int(round(min_x)), int(round(min_y)), int(round(max_x)), int(round(max_y))


def _get_peak_from_converter(
    converter: GeoTIFFConverter,
    world_offset_x: int,
    world_offset_z: int,
) -> dict:
    """Find the highest valid sample in a loaded GeoTIFF."""
    peak_data = converter.data.astype(np.float32, copy=True)

    if converter.dataset.nodata is not None:
        valid_mask = peak_data > converter.dataset.nodata
        if np.any(valid_mask):
            peak_data[~valid_mask] = np.min(peak_data[valid_mask])

    peak_index = int(np.argmax(peak_data))
    peak_row, peak_col = np.unravel_index(peak_index, peak_data.shape)

    return {
        "height": float(peak_data[peak_row, peak_col]),
        "local_x": world_offset_x + int(peak_col),
        "local_z": world_offset_z + int(peak_row),
        "tile": converter.input_path.stem,
    }


def batch_convert_files(
    tiff_files: list[Path],
    output_dir: Path,
    output_format: str = "chunks",
    chunk_size: int = 256,
    chunk_format: str = "raw",
    min_height: Optional[float] = None,
    max_height: Optional[float] = None,
) -> Path:
    """Convert a set of GeoTIFFs into one consistent terrain dataset."""
    if not tiff_files:
        raise ValueError("No GeoTIFF files provided for batch conversion.")

    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    min_x, min_y, max_x, max_y = discover_dataset_bounds(tiff_files)
    print(f"Global origin: E {min_x}, N {min_y}")

    dataset_peak = None
    converted_tiles = []

    for tiff_path in sorted(tiff_files):
        converter = GeoTIFFConverter(tiff_path).load()

        tile_output = output_dir / tiff_path.stem
        tile_output.mkdir(parents=True, exist_ok=True)

        world_offset_x = int(round(converter.metadata["bounds"].left - min_x))
        world_offset_z = int(round(converter.metadata["bounds"].bottom - min_y))

        print(f"  Offset for {tiff_path.stem}: ({world_offset_x}, {world_offset_z})")

        peak = _get_peak_from_converter(converter, world_offset_x, world_offset_z)
        if dataset_peak is None or peak["height"] > dataset_peak["height"]:
            dataset_peak = peak

        if output_format == "chunks":
            converter.export_chunks(
                tile_output,
                chunk_size=chunk_size,
                format=chunk_format,
                world_offset_x=world_offset_x,
                world_offset_z=world_offset_z,
            )
        elif output_format == "png":
            converter.export_png(
                tile_output / f"{tiff_path.stem}.png",
                min_height=min_height,
                max_height=max_height,
            )
        else:
            converter.export_r16(
                tile_output / f"{tiff_path.stem}.r16",
                min_height=min_height,
                max_height=max_height,
            )

        converted_tiles.append(
            {
                "tile": tiff_path.stem,
                "local_offset_x": world_offset_x,
                "local_offset_z": world_offset_z,
            }
        )
        converter.close()

    dataset_manifest = {
        "crs": "EPSG:3006",
        "origin_easting": min_x,
        "origin_northing": min_y,
        "max_easting": max_x,
        "max_northing": max_y,
        "chunk_size": chunk_size,
        "chunk_overlap": 1,
        "chunk_step": chunk_size - 1,
        "output_format": output_format,
        "chunk_format": chunk_format if output_format == "chunks" else output_format,
        "peak_local_x": dataset_peak["local_x"] if dataset_peak else 0,
        "peak_local_z": dataset_peak["local_z"] if dataset_peak else 0,
        "peak_height": dataset_peak["height"] if dataset_peak else 0.0,
        "peak_tile": dataset_peak["tile"] if dataset_peak else "",
        "tiles": converted_tiles,
    }

    manifest_path = output_dir / "dataset_manifest.json"
    with open(manifest_path, "w") as f:
        json.dump(dataset_manifest, f, indent=2)

    print(f"Wrote dataset manifest: {manifest_path}")
    return manifest_path


def main():
    parser = argparse.ArgumentParser(
        description="Convert Lantmäteriet GeoTIFF to Godot heightmap formats"
    )
    parser.add_argument(
        "input",
        type=Path,
        help="Input GeoTIFF file or directory"
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("terrain_data/raw_height"),
        help="Output directory"
    )
    parser.add_argument(
        "--format",
        choices=["png", "r16", "chunks"],
        default="chunks",
        help="Output format"
    )
    parser.add_argument(
        "--chunk-size",
        type=int,
        default=256,
        help="Chunk size for 'chunks' format"
    )
    parser.add_argument(
        "--chunk-format",
        choices=["png", "r16", "raw"],
        default="raw",
        help="Format for chunk files (png, r16, or raw for float32)"
    )
    parser.add_argument(
        "--min-height",
        type=float,
        default=None,
        help="Minimum height for normalization (auto-detect if not specified)"
    )
    parser.add_argument(
        "--max-height",
        type=float,
        default=None,
        help="Maximum height for normalization (auto-detect if not specified)"
    )
    parser.add_argument(
        "--batch",
        action="store_true",
        help="Process all GeoTIFFs in input directory"
    )
    
    args = parser.parse_args()
    
    if args.batch:
        # Process all GeoTIFFs in directory
        tiff_files = list(args.input.glob("*.tif"))
        print(f"Found {len(tiff_files)} GeoTIFF files")
        batch_convert_files(
            tiff_files,
            args.output,
            output_format=args.format,
            chunk_size=args.chunk_size,
            chunk_format=args.chunk_format,
            min_height=args.min_height,
            max_height=args.max_height,
        )
    else:
        # Process single file
        converter = GeoTIFFConverter(args.input).load()
        args.output.mkdir(parents=True, exist_ok=True)
        
        if args.format == "chunks":
            converter.export_chunks(
                args.output,
                chunk_size=args.chunk_size,
                format=args.chunk_format
            )
        elif args.format == "png":
            converter.export_png(
                args.output / f"{args.input.stem}.png",
                min_height=args.min_height,
                max_height=args.max_height
            )
        else:  # r16
            converter.export_r16(
                args.output / f"{args.input.stem}.r16",
                min_height=args.min_height,
                max_height=args.max_height
            )
        
        converter.close()
    
    print("\nConversion complete!")


if __name__ == "__main__":
    main()
