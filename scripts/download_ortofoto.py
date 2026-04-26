#!/usr/bin/env python3
"""
STAC API client for Lantmäteriet Ortofoto (aerial imagery).

Mirrors download_terrain.py for color imagery. Uses the same Geotorget
credentials as the heightmap pipeline — see docs/LANTMATERIET_SETUP.md
for how to register, order Ortofoto access, and set
LANTMATERIET_USERNAME / LANTMATERIET_PASSWORD.

The STAC base URL differs between products. As of writing the ortofoto
STAC lives at:

    https://api.lantmateriet.se/stac-bild/v1

If Lantmäteriet has moved it, run with --list-collections first to
discover the current collection IDs, or browse
https://geotorget.lantmateriet.se for the active endpoint of
"Ortofoto Nedladdning".

Usage:
    python scripts/download_ortofoto.py --list-collections
    python scripts/download_ortofoto.py --bbox 13.0 63.3 13.2 63.5 \\
        --collection <id-from-list> \\
        --output terrain_data/raw_ortho
"""

import argparse
import json
import os
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import requests
from requests.auth import HTTPBasicAuth

try:
    from dotenv import load_dotenv
    env_path = Path(__file__).parent.parent / ".env"
    if env_path.exists():
        load_dotenv(env_path)
except ImportError:
    pass


DEFAULT_BASE_URL = "https://api.lantmateriet.se/stac-bild/v1"


class OrtofotoSTACClient:
    def __init__(
        self,
        base_url: str = DEFAULT_BASE_URL,
        username: Optional[str] = None,
        password: Optional[str] = None,
    ):
        self.base_url = base_url.rstrip("/")
        self.username = username or os.environ.get("LANTMATERIET_USERNAME")
        self.password = password or os.environ.get("LANTMATERIET_PASSWORD")
        if not self.username or not self.password:
            raise ValueError(
                "Set LANTMATERIET_USERNAME and LANTMATERIET_PASSWORD or pass --user/--pass."
            )
        self.session = requests.Session()
        self.session.auth = HTTPBasicAuth(self.username, self.password)

    def collections(self) -> List[Dict]:
        r = self.session.get(f"{self.base_url}/collections")
        r.raise_for_status()
        return r.json().get("collections", [])

    def search(
        self,
        bbox: Tuple[float, float, float, float],
        collection: Optional[str] = None,
        limit: int = 200,
    ) -> List[Dict]:
        body = {"bbox": list(bbox), "limit": limit}
        if collection:
            body["collections"] = [collection]
        r = self.session.post(
            f"{self.base_url}/search",
            json=body,
            headers={"Content-Type": "application/json"},
        )
        r.raise_for_status()
        return r.json().get("features", [])

    def download_item(
        self,
        item: Dict,
        output_dir: Path,
        overwrite: bool = False,
    ) -> Optional[Path]:
        assets = item.get("assets", {})
        asset = None
        for key, val in assets.items():
            href = val.get("href", "")
            if href.endswith((".tif", ".tiff")):
                asset = val
                break
        if not asset:
            print(f"  no GeoTIFF asset in item {item.get('id')}")
            return None

        href = asset["href"]
        filename = href.split("/")[-1]
        output_path = output_dir / filename
        if output_path.exists() and not overwrite:
            print(f"  exists: {filename}")
            return output_path

        output_dir.mkdir(parents=True, exist_ok=True)
        print(f"  downloading {filename}...")
        with self.session.get(href, stream=True) as r:
            r.raise_for_status()
            total = int(r.headers.get("content-length", 0))
            done = 0
            with open(output_path, "wb") as f:
                for chunk in r.iter_content(chunk_size=1 << 16):
                    f.write(chunk)
                    done += len(chunk)
                    if total:
                        print(
                            f"    {done * 100 // total:3d}% ({done >> 20} / {total >> 20} MiB)",
                            end="\r",
                        )
        print()
        return output_path


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--base-url", default=DEFAULT_BASE_URL)
    p.add_argument("--collection", help="STAC collection ID (auto-detect if omitted)")
    p.add_argument(
        "--bbox",
        nargs=4,
        type=float,
        metavar=("MIN_LON", "MIN_LAT", "MAX_LON", "MAX_LAT"),
        help="Bounding box in WGS84",
    )
    p.add_argument("--output", default="terrain_data/raw_ortho")
    p.add_argument("--list-collections", action="store_true")
    p.add_argument("--user")
    p.add_argument("--password", dest="password_arg")
    p.add_argument("--overwrite", action="store_true")
    p.add_argument("--limit", type=int, default=200)
    args = p.parse_args()

    client = OrtofotoSTACClient(
        base_url=args.base_url,
        username=args.user,
        password=args.password_arg,
    )

    if args.list_collections:
        print("Collections:")
        for c in client.collections():
            print(f"  {c.get('id'):30s}  {c.get('title','')}")
        return

    if not args.bbox:
        p.error("--bbox is required unless --list-collections")

    items = client.search(tuple(args.bbox), collection=args.collection, limit=args.limit)
    print(f"Found {len(items)} item(s)")
    out = Path(args.output)
    for item in items:
        client.download_item(item, out, overwrite=args.overwrite)


if __name__ == "__main__":
    main()
