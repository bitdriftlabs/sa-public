#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE="stevelerner/bitdrift-shop-backend"
VERSION=${1:-"latest"}

docker build --no-cache -t $IMAGE:$VERSION .
echo "Built $IMAGE:$VERSION"
