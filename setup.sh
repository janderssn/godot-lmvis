#!/bin/bash
# Quick setup script for Åre Steep
# Run this from the project root directory

cd "$(dirname "$0")"

echo "========================================"
echo "  Åre Steep - Environment Setup"
echo "========================================"
echo ""

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is not installed"
    echo "   Install Python 3.10+ from https://python.org"
    exit 1
fi

# Run the Python setup script
python3 scripts/setup.py
