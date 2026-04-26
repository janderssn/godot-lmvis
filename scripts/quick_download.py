#!/usr/bin/env python3
"""
Quick terrain download helper for godot-lmvis.
Simplifies downloading terrain data with sensible defaults.

Usage:
    export LANTMATERIET_USERNAME="your_email"
    export LANTMATERIET_PASSWORD="your_password"
    python quick_download.py central --process
"""

import argparse
import sys
import os
from pathlib import Path

# Add scripts directory to path
sys.path.insert(0, str(Path(__file__).parent))

from download_terrain import LantmaterietSTACClient, ARE_REGIONS
from convert_terrain import batch_convert_files


def main():
    parser = argparse.ArgumentParser(
        description="Quick terrain download for godot-lmvis",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment variables:
  LANTMATERIET_USERNAME    Your Geotorget email/username
  LANTMATERIET_PASSWORD    Your Geotorget password

Examples:
  # Download just central Åre (recommended for testing)
  python quick_download.py central
  
  # Download and automatically process
  python quick_download.py central --process
  
  # Download full Åre region (all ski areas)
  python quick_download.py full --process
  
  # Download specific area with verbose output
  python quick_download.py duved --verbose

Available areas:
  central    - Central Åre, Kabinbanan (1-4 tiles, ~200-400MB)
  bjornen    - Björnen area (1-2 tiles, ~100-200MB)
  duved      - Duved area (1-2 tiles, ~100-200MB)
  tegefjall  - Tegefjäll (1-2 tiles, ~100-200MB)
  full       - All of Åre (10-20 tiles, ~1-2GB)
        """
    )
    
    parser.add_argument(
        "area",
        choices=["central", "bjornen", "duved", "tegefjall", "full"],
        help="Which area of Åre to download"
    )
    
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("terrain_data/raw"),
        help="Output directory (default: terrain_data/raw)"
    )
    
    parser.add_argument(
        "--process",
        action="store_true",
        help="Automatically convert to Godot format after download"
    )
    
    parser.add_argument(
        "--chunk-size",
        type=int,
        default=256,
        help="Chunk size for processing (default: 256)"
    )
    
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print detailed progress"
    )
    
    parser.add_argument(
        "--user",
        "--username",
        type=str,
        default=os.environ.get("LANTMATERIET_USERNAME"),
        help="Geotorget username (or set LANTMATERIET_USERNAME env var)"
    )
    
    parser.add_argument(
        "--pass",
        "--password",
        type=str,
        default=os.environ.get("LANTMATERIET_PASSWORD"),
        help="Geotorget password (or set LANTMATERIET_PASSWORD env var)"
    )
    
    args = parser.parse_args()
    
    # Map short names to region keys
    region_map = {
        "central": "are_central",
        "bjornen": "are_bjornen",
        "duved": "are_duved",
        "tegefjall": "are_tegefjall",
        "full": "are_full"
    }
    
    region = region_map[args.area]
    bbox = ARE_REGIONS[region]
    
    # Check for credentials
    username = args.user
    password = getattr(args, 'pass')
    
    if not username or not password:
        print("❌ Lantmäteriet credentials not set!")
        print("\nTo get credentials:")
        print("1. Register at https://geotorget.lantmateriet.se")
        print("2. Order access to 'Markhöjdmodell Nedladdning'")
        print("\nThen set environment variables:")
        print("  export LANTMATERIET_USERNAME='your_email@example.com'")
        print("  export LANTMATERIET_PASSWORD='your_password'")
        print("\nOr use command line options:")
        print("  python quick_download.py central --user email --pass password")
        print("\nSee docs/LANTMATERIET_SETUP.md for detailed instructions.")
        sys.exit(1)
    
    if args.verbose:
        print(f"Downloading terrain for: {args.area}")
        print(f"Bounding box (WGS84): {bbox}")
        print(f"Output: {args.output}")
    
    # Create client and download
    try:
        client = LantmaterietSTACClient(username=username, password=password)
    except ValueError as e:
        print(f"Error: {e}")
        return 1
    
    try:
        print(f"Searching for tiles in {args.area}...")
        items = client.search_items(bbox=bbox)
        
        if not items:
            print("❌ No tiles found for this area")
            print("Try a different area or check your bounding box")
            sys.exit(1)
        
        print(f"Found {len(items)} tile(s)")
        
        # Calculate total size estimate
        total_size_mb = len(items) * 75  # Rough estimate: 75MB per tile
        print(f"Estimated download size: {total_size_mb} MB")
        
        # Download all tiles
        downloaded = []
        for i, item in enumerate(items, 1):
            print(f"\n[{i}/{len(items)}] Processing {item['id']}...")
            path = client.download_asset(item, output_dir=args.output)
            if path:
                downloaded.append(path)
        
        print(f"\n{'='*60}")
        print(f"Downloaded {len(downloaded)} file(s) to {args.output}")
        print(f"{'='*60}")
        
        # Process if requested
        if args.process and downloaded:
            print("\nProcessing terrain data for Godot...")
            
            processed_dir = Path("terrain_data/raw_height")
            batch_convert_files(
                downloaded,
                processed_dir,
                output_format="chunks",
                chunk_size=args.chunk_size,
                chunk_format="raw",
            )
            print(f"\n✅ Processed terrain ready in {processed_dir}")
        elif downloaded and not args.process:
            print("\n⚠️  Downloaded but not processed. To process, run:")
            print("  python scripts/convert_terrain.py --batch --input terrain_data/raw --output terrain_data/raw_height --chunk-format raw")
        
        print("\n🎉 Done! You can now open the project in Godot.")
        
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
