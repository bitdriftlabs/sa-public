#!/bin/bash
# Build the image from source, for backend development. Normal use pulls the
# published image instead — see ../start-backend-docker.sh.
set -e
TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$TOOLS/ensure-docker.sh"
cd "$TOOLS/.."

IMAGE="stevelerner/bitdrift-shop-backend"
VERSION=${1:-"latest"}
# The default image has no OpenTelemetry (smaller). `build.sh otel` builds the :otel variant that has it,
# for the o11y compose file; WITH_OTEL=1 forces it into any other tag.
if [ "$VERSION" = "otel" ]; then WITH_OTEL=1; fi

docker build --no-cache --build-arg WITH_OTEL=${WITH_OTEL:-0} -t $IMAGE:$VERSION .
echo "Built $IMAGE:$VERSION"
