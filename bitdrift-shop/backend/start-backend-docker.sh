#!/bin/bash
# Start the backend: pull the published image and run it. The usual entry point.
# GRAFANA_ALLOY_ENABLED=true (environment or .env) adds the Grafana Alloy collector; see README.md.
set -e
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
./tools/ensure-docker.sh
source ./tools/alloy.sh
docker compose $COMPOSE down --remove-orphans
TAG=${1:-$DEFAULT_TAG} docker compose $COMPOSE up --pull always
