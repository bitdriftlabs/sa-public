#!/bin/bash
# Start the backend with chaos mode on — injects latency, 4xx/5xx, truncated
# payloads and payment failures. See README.md for the fault table.
# GRAFANA_ALLOY_ENABLED=true (environment or .env) adds the Grafana Alloy collector.
set -e
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
./tools/ensure-docker.sh
source ./tools/alloy.sh
docker compose $COMPOSE down --remove-orphans
TAG=${1:-$DEFAULT_TAG} CHAOS_MODE=1 docker compose $COMPOSE up --pull always
