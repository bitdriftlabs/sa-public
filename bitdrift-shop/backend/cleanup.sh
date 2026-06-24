#!/usr/bin/env bash
# Cleanup script for the ShopDemo backend
# Removes generated/cached files to restore a clean state

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pushd "$SCRIPT_DIR" > /dev/null

echo "Cleaning up backend..."

# Python cache
if [ -d "__pycache__" ]; then
    rm -rf __pycache__
    echo "  Removed __pycache__/"
fi
find . -name "*.pyc" -delete 2>/dev/null && echo "  Removed .pyc files" || true

# Virtual environment
if [ -d "venv" ]; then
    rm -rf venv
    echo "  Removed venv/"
fi

# Generated images are kept — they are needed by the server

popd > /dev/null
echo "Done. Run 'python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt' to set up again."
