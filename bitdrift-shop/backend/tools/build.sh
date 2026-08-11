#!/bin/bash
# Build the image from source, for backend development. Normal use pulls the
# published image instead — see ../start-backend-docker.sh.
set -e
TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$TOOLS/ensure-docker.sh"
cd "$TOOLS/.."

IMAGE="stevelerner/bitdrift-shop-backend"
VERSION=${1:-"latest"}

docker build --no-cache -t $IMAGE:$VERSION .
echo "Built $IMAGE:$VERSION"
