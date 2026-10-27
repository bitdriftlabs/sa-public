#!/bin/bash
# Push images that tools/build.sh already built (this script does not build):
#   dockerhub-push.sh            push :latest (the default image, no OpenTelemetry)
#   dockerhub-push.sh otel       push :otel only (the OpenTelemetry variant, from `build.sh otel`)
#   dockerhub-push.sh v1.2.0     push :latest, and :latest re-tagged as :v1.2.0
set -e

IMAGE="stevelerner/bitdrift-shop-backend"
VERSION=${1:-"latest"}

if [ "$VERSION" = "otel" ]; then
    docker push $IMAGE:otel
    echo "Pushed $IMAGE:otel"
    exit 0
fi

docker push $IMAGE:latest
if [ "$VERSION" != "latest" ]; then
    docker tag $IMAGE:latest $IMAGE:$VERSION
    docker push $IMAGE:$VERSION
fi
echo "Pushed $IMAGE:latest${VERSION:+ and $IMAGE:$VERSION}"
