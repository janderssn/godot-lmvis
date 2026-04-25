#!/usr/bin/env python3
"""
Setup script for Åre Steep game development environment.
Checks dependencies, API access, and guides through initial setup.
"""

import os
import sys
import subprocess
from pathlib import Path

def print_header(text):
    print(f"\n{'='*60}")
    print(f"  {text}")
    print(f"{'='*60}")

def print_step(step_num, text):
    print(f"\n[Step {step_num}] {text}")

def check_python_version():
    """Check if Python 3.10+ is installed."""
    version = sys.version_info
    if version.major < 3 or (version.major == 3 and version.minor < 10):
        print(f"❌ Python {version.major}.{version.minor} found, but 3.10+ is required")
        return False
    print(f"✅ Python {version.major}.{version.minor}.{version.micro}")
    return True

def check_godot():
    """Check if Godot 4 is installed."""
    godot_names = ["godot", "godot4", "Godot", "Godot4"]
    
    for name in godot_names:
        result = subprocess.run(["which", name], capture_output=True)
        if result.returncode == 0:
            print(f"✅ Godot found: {name}")
            # Try to get version
            try:
                version_result = subprocess.run([name, "--version"], capture_output=True, text=True, timeout=5)
                if version_result.returncode == 0:
                    print(f"   Version: {version_result.stdout.strip()}")
            except:
                pass
            return True
    
    print("❌ Godot 4 not found in PATH")
    print("   Download from: https://godotengine.org/download")
    return False

def check_python_dependencies():
    """Check if required Python packages are installed."""
    required = ["requests", "rasterio", "numpy", "PIL"]
    missing = []
    
    for package in required:
        try:
            __import__(package.lower() if package != "PIL" else "PIL")
        except ImportError:
            missing.append(package)
    
    if missing:
        print(f"❌ Missing Python packages: {', '.join(missing)}")
        print(f"   Install with: pip install -r scripts/requirements.txt")
        return False
    
    print("✅ All Python dependencies installed")
    return True

def check_lantmateriet_credentials():
    """Check if Lantmäteriet credentials are configured."""
    username = os.environ.get("LANTMATERIET_USERNAME")
    password = os.environ.get("LANTMATERIET_PASSWORD")
    
    if not username:
        print("❌ LANTMATERIET_USERNAME not set")
        print("   Set it: export LANTMATERIET_USERNAME='your_email@example.com'")
        return False
    
    if not password:
        print("❌ LANTMATERIET_PASSWORD not set")
        print("   Set it: export LANTMATERIET_PASSWORD='your_password'")
        return False
    
    masked_user = username[:3] + "***" + username.split("@")[-1]
    print(f"✅ Lantmäteriet credentials configured")
    print(f"   Username: {masked_user}")
    return True

def check_terrain_data():
    """Check if terrain data exists."""
    raw_dir = Path("terrain_data/raw")
    processed_dir = Path("terrain_data/raw_height")
    
    raw_tiffs = list(raw_dir.glob("*.tif")) if raw_dir.exists() else []
    processed_manifests = list(processed_dir.glob("**/chunks_manifest.json")) if processed_dir.exists() else []
    
    if processed_manifests:
        print(f"✅ Processed terrain data found ({len(processed_manifests)} tile(s))")
        return True
    elif raw_tiffs:
        print(f"⚠️  Raw terrain data found ({len(raw_tiffs)} file(s)), but not processed")
        print("   Run: python scripts/convert_terrain.py --batch --input terrain_data/raw --output terrain_data/raw_height --chunk-format raw")
        return False
    else:
        print("❌ No terrain data found")
        print("   Run: python scripts/download_terrain.py --region are_central")
        return False

def check_godot_project():
    """Check Godot project structure."""
    project_file = Path("project.godot")
    
    if not project_file.exists():
        print("❌ Godot project file not found")
        return False
    
    print("✅ Godot project found")
    
    # Check for scenes directory
    scenes_dir = Path("scenes")
    main_scene = scenes_dir / "main.tscn"
    
    if main_scene.exists():
        print("✅ Main scene exists")
    else:
        print("⚠️  Main scene not created yet")
        print("   Create scenes/main.tscn in Godot editor")
    
    return True

def test_api_connection():
    """Test connection to Lantmäteriet API."""
    try:
        import requests
        from requests.auth import HTTPBasicAuth
    except ImportError:
        print("⚠️  Cannot test API (requests not installed)")
        return False
    
    username = os.environ.get("LANTMATERIET_USERNAME")
    password = os.environ.get("LANTMATERIET_PASSWORD")
    
    if not username or not password:
        return False
    
    print("   Testing API connection...")
    
    try:
        url = "https://api.lantmateriet.se/stac-hojd/v1/collections"
        auth = HTTPBasicAuth(username, password)
        
        response = requests.get(url, auth=auth, timeout=10)
        
        if response.status_code == 200:
            print("✅ API connection successful")
            data = response.json()
            collections = [c.get("id") for c in data.get("collections", [])]
            print(f"   Available collections: {', '.join(collections[:3])}")
            if len(collections) > 3:
                print(f"   ... and {len(collections) - 3} more")
            return True
        elif response.status_code == 401:
            print("❌ API authentication failed")
            print("   Check that your username and password are correct")
            return False
        else:
            print(f"⚠️  API returned status {response.status_code}")
            return False
            
    except Exception as e:
        print(f"⚠️  Could not test API: {e}")
        return False

def main():
    print_header("Åre Steep - Development Environment Setup")
    
    print("\nThis script checks your development environment.")
    print("Follow the steps below to get everything working.\n")
    
    results = {
        "Python": check_python_version(),
        "Godot": check_godot(),
        "Python Dependencies": check_python_dependencies(),
        "Lantmäteriet Credentials": check_lantmateriet_credentials(),
        "Terrain Data": check_terrain_data(),
        "Godot Project": check_godot_project(),
    }
    
    # Test API only if credentials are present
    if results["Lantmäteriet Credentials"]:
        results["API Connection"] = test_api_connection()
    
    # Summary
    print_header("Setup Summary")
    
    all_good = all(results.values())
    
    for name, status in results.items():
        symbol = "✅" if status else "❌"
        print(f"{symbol} {name}")
    
    print()
    
    if all_good:
        print("🎉 All checks passed! You're ready to develop.")
        print("\nNext steps:")
        print("1. Open the project in Godot")
        print("2. Create scenes/main.tscn")
        print("3. Run the game!")
    else:
        print("⚠️  Some checks failed. Fix the issues above and run again.")
        print("\nFor detailed instructions, see:")
        print("  - docs/LANTMATERIET_SETUP.md (API credentials setup)")
        print("  - README.md (general setup)")
    
    return 0 if all_good else 1

if __name__ == "__main__":
    sys.exit(main())
