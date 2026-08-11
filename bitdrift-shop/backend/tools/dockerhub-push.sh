#!/bin/bash
set -e

IMAGE="stevelerner/bitdrift-shop-backend"
VERSION=${1:-"latest"}

docker push $IMAGE:latest
if [ "$VERSION" != "latest" ]; then
    docker tag $IMAGE:latest $IMAGE:$VERSION
    docker push $IMAGE:$VERSION
fi
echo "Pushed $IMAGE:latest${VERSION:+ and $IMAGE:$VERSION}"
