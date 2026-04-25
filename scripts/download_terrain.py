#!/usr/bin/env python3
"""
STAC API Client for Lantmäteriet Markhöjdmodell (1m resolution)
Downloads terrain tiles for Åre region using HTTP Basic Auth

Usage:
    export LANTMATERIET_USERNAME="your_email"
    export LANTMATERIET_PASSWORD="your_password"
    python download_terrain.py --region are_central

Or create a .env file with:
    LANTMATERIET_USERNAME=your_email@example.com
    LANTMATERIET_PASSWORD=your_password
"""

import requests
import json
import os
from pathlib import Path
from typing import List, Dict, Optional, Tuple
from requests.auth import HTTPBasicAuth
import argparse

# Try to load .env file if python-dotenv is available
try:
    from dotenv import load_dotenv
    # Look for .env in project root (parent of scripts directory)
    env_path = Path(__file__).parent.parent / ".env"
    if env_path.exists():
        load_dotenv(env_path)
except ImportError:
    pass  # python-dotenv not installed, rely on environment variables


class LantmaterietSTACClient:
    """
    Client for accessing Lantmäteriets STAC API for Markhöjdmodell (height data).
    
    API endpoint: https://api.lantmateriet.se/stac-hojd/v1/
    Authentication: HTTP Basic Auth with Geotorget username/password
    
    Åre ski resort coordinates (SWEREF 99 TM / EPSG:3006):
    - Central Åre: approximately E 377000, N 7035000
    - WGS84 equivalent: lon ~13.0-13.2, lat ~63.3-63.5
    """
    
    BASE_URL = "https://api.lantmateriet.se/stac-hojd/v1"
    
    def __init__(self, username: Optional[str] = None, password: Optional[str] = None):
        """
        Initialize client with Basic Auth credentials.
        
        Args:
            username: Geotorget email/username (or set LANTMATERIET_USERNAME env var)
            password: Geotorget password (or set LANTMATERIET_PASSWORD env var)
        """
        self.username = username or os.environ.get("LANTMATERIET_USERNAME")
        self.password = password or os.environ.get("LANTMATERIET_PASSWORD")
        
        if not self.username or not self.password:
            raise ValueError(
                "Username and password required. Set LANTMATERIET_USERNAME "
                "and LANTMATERIET_PASSWORD environment variables."
            )
        
        self.auth = HTTPBasicAuth(self.username, self.password)
        self.session = requests.Session()
        self.session.auth = self.auth
    
    def get_catalog(self) -> Dict:
        """Get the root catalog information."""
        response = self.session.get(f"{self.BASE_URL}/")
        response.raise_for_status()
        return response.json()
    
    def get_collections(self) -> List[Dict]:
        """Get available STAC collections."""
        response = self.session.get(f"{self.BASE_URL}/collections")
        response.raise_for_status()
        return response.json().get("collections", [])
    
    def search_items(
        self,
        bbox: Tuple[float, float, float, float],
        collection: Optional[str] = None,
        limit: int = 100
    ) -> List[Dict]:
        """
        Search for STAC items within a bounding box.
        
        Args:
            bbox: (min_x, min_y, max_x, max_y) - WGS84 coordinates (lon/lat)
            collection: Collection ID (e.g., 'mhm-63_7')
            limit: Maximum number of results
            
        Returns:
            List of STAC item dictionaries
        """
        # Use POST search which works better with bbox
        url = f"{self.BASE_URL}/search"
        headers = {"Content-Type": "application/json"}
        data = {
            "bbox": list(bbox),
            "limit": limit
        }
        
        if collection:
            data["collections"] = [collection]
        
        response = self.session.post(url, json=data, headers=headers)
        response.raise_for_status()
        
        return response.json().get("features", [])
    
    def download_asset(
        self,
        item: Dict,
        asset_key: str = "data",
        output_dir: Path = Path("terrain_data/raw"),
        overwrite: bool = False
    ) -> Optional[Path]:
        """
        Download a specific asset from a STAC item.
        
        Args:
            item: STAC item dictionary
            asset_key: Key of the asset to download (usually 'data' for GeoTIFF)
            output_dir: Directory to save the file
            overwrite: Whether to overwrite existing files
            
        Returns:
            Path to downloaded file, or None if download failed
        """
        assets = item.get("assets", {})
        
        # Find the actual data asset (might be named 'data', 'grid', etc.)
        asset = None
        if asset_key in assets:
            asset = assets[asset_key]
        else:
            # Try to find any .tif asset
            for key, val in assets.items():
                href = val.get("href", "")
                if href.endswith(".tif") or href.endswith(".tiff"):
                    asset = val
                    asset_key = key
                    break
        
        if not asset:
            print(f"No suitable asset found in item {item.get('id', 'unknown')}")
            print(f"  Available assets: {list(assets.keys())}")
            return None
        
        href = asset.get("href")
        if not href:
            print(f"No href found for asset '{asset_key}'")
            return None
        
        # Determine filename
        filename = href.split("/")[-1]
        if not filename.endswith(".tif"):
            filename = f"{item['id']}.tif"
        
        output_path = output_dir / filename
        
        if output_path.exists() and not overwrite:
            print(f"File already exists: {output_path}")
            return output_path
        
        output_dir.mkdir(parents=True, exist_ok=True)
        
        print(f"Downloading {filename}...")
        
        try:
            with self.session.get(href, stream=True) as response:
                response.raise_for_status()
                
                total_size = int(response.headers.get('content-length', 0))
                downloaded = 0
                
                with open(output_path, "wb") as f:
                    for chunk in response.iter_content(chunk_size=8192):
                        if chunk:
                            f.write(chunk)
                            downloaded += len(chunk)
                            if total_size > 0:
                                percent = (downloaded / total_size) * 100
                                print(f"\r  Progress: {percent:.1f}%", end="", flush=True)
                
                print()  # New line after progress
            
            file_size = output_path.stat().st_size / (1024 * 1024)
            print(f"  Saved: {filename} ({file_size:.2f} MB)")
            return output_path
            
        except Exception as e:
            print(f"\n  Failed to download {filename}: {e}")
            if output_path.exists():
                output_path.unlink()
            return None


# Predefined bounding boxes for Åre region
# In WGS84 (EPSG:4326) - lon/lat format for STAC API
ARE_REGIONS = {
    "are_central": (12.95, 63.38, 13.15, 63.42),    # Central Åre, Kabinbanan
    "are_bjornen": (12.95, 63.28, 13.10, 63.38),    # Björnen area
    "are_duved": (12.70, 63.40, 12.90, 63.50),      # Duved area
    "are_tegefjall": (12.85, 63.25, 13.00, 63.35),  # Tegefjäll
    "are_full": (12.60, 63.20, 13.50, 63.65),       # Full Åre region
}

# Keep alias for backward compatibility
ARE_REGIONS_WGS84 = ARE_REGIONS


def main():
    parser = argparse.ArgumentParser(
        description="Download terrain data from Lantmäteriets STAC API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment variables:
  LANTMATERIET_USERNAME    Your Geotorget email/username
  LANTMATERIET_PASSWORD    Your Geotorget password

Examples:
  # Download central Åre
  python download_terrain.py --region are_central
  
  # Download with explicit credentials
  python download_terrain.py --region are_central --user email --pass password
  
  # List available collections
  python download_terrain.py --list-collections
  
  # Search specific area with custom bbox (SWEREF 99 TM)
  python download_terrain.py --bbox 377000 7035000 379500 7037500
        """
    )
    
    parser.add_argument(
        "--region",
        choices=list(ARE_REGIONS.keys()),
        default="are_central",
        help="Predefined region to download (default: are_central)"
    )
    parser.add_argument(
        "--bbox",
        type=float,
        nargs=4,
        metavar=("MIN_X", "MIN_Y", "MAX_X", "MAX_Y"),
        help="Custom bounding box (SWEREF 99 TM coordinates recommended)"
    )
    parser.add_argument(
        "--collection",
        type=str,
        default=None,
        help="STAC collection ID (auto-detected if not specified)"
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("terrain_data/raw"),
        help="Output directory for downloaded files (default: terrain_data/raw)"
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
    parser.add_argument(
        "--list-collections",
        action="store_true",
        help="List available collections and exit"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be downloaded without downloading"
    )
    
    args = parser.parse_args()
    
    # Initialize client
    try:
        client = LantmaterietSTACClient(
            username=args.user,
            password=getattr(args, 'pass')
        )
    except ValueError as e:
        print(f"Error: {e}")
        print("\nSet credentials via environment variables:")
        print("  export LANTMATERIET_USERNAME='your_email'")
        print("  export LANTMATERIET_PASSWORD='your_password'")
        return 1
    
    if args.list_collections:
        print("Fetching collections...")
        try:
            collections = client.get_collections()
            print(f"\nFound {len(collections)} collection(s):\n")
            for collection in collections:
                print(f"  ID: {collection['id']}")
                print(f"  Title: {collection.get('title', 'N/A')}")
                print(f"  Description: {collection.get('description', 'N/A')[:100]}...")
                print()
        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 401:
                print("❌ Authentication failed. Check your username and password.")
            else:
                print(f"❌ Error: {e}")
        return 0
    
    # Determine bounding box
    if args.bbox:
        bbox = tuple(args.bbox)
        print(f"Using custom bounding box: {bbox}")
    else:
        bbox = ARE_REGIONS[args.region]
        print(f"Using region: {args.region}")
        print(f"Bounding box (WGS84): {bbox}")
    
    try:
        print(f"\nSearching for tiles...")
        items = client.search_items(bbox=bbox, collection=args.collection)
        print(f"Found {len(items)} tile(s)")
        
        if not items:
            print("\nNo tiles found. Try:")
            print("  - A different bounding box")
            print("  - List collections to verify the collection ID")
            return 0
        
        if args.dry_run:
            print("\nTiles that would be downloaded:")
            for item in items:
                print(f"  - {item['id']}")
                assets = item.get("assets", {})
                for key in assets.keys():
                    print(f"    Asset: {key}")
            return 0
        
        # Download all tiles
        print(f"\nDownloading to: {args.output}")
        downloaded = []
        for i, item in enumerate(items, 1):
            print(f"\n[{i}/{len(items)}] Processing {item['id']}...")
            path = client.download_asset(item, output_dir=args.output)
            if path:
                downloaded.append(path)
        
        print(f"\n{'='*60}")
        print(f"Downloaded {len(downloaded)} file(s) to {args.output}")
        print(f"{'='*60}")
        
        if downloaded:
            print("\nNext steps:")
            print("  1. Convert the GeoTIFFs:")
            print("     python scripts/convert_terrain.py --batch --input terrain_data/raw --output terrain_data/raw_height --chunk-format raw")
            print("  2. Open the project in Godot")
        
    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 401:
            print("\n❌ Authentication failed.")
            print("Check your username and password.")
            print("\nMake sure you have:")
            print("  1. Registered at https://geotorget.lantmateriet.se")
            print("  2. Ordered access to 'Markhöjdmodell Nedladdning'")
            print("  3. Set the correct username and password")
        else:
            print(f"\n❌ Error: {e}")
        return 1
    
    return 0


if __name__ == "__main__":
    exit(main())
