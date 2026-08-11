#!/bin/bash
# Start the backend attached to the external `tinyolly-network`, for running
# against a local OpenTelemetry collector. Otherwise identical to the standard
# start script. Requires: docker network create tinyolly-network
set -e
TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$TOOLS/ensure-docker.sh"
cd "$TOOLS/.."
COMPOSE="-f docker-compose.yml -f docker-compose.o11y.yml"
docker compose $COMPOSE down
TAG=${1:-latest} docker compose $COMPOSE up --pull always
