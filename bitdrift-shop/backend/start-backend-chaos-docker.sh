#!/bin/bash
# Start the backend with chaos mode on — injects latency, 4xx/5xx, truncated
# payloads and payment failures. See README.md for the fault table.
set -e
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
./tools/ensure-docker.sh
docker compose down
TAG=${1:-latest} CHAOS_MODE=1 docker compose up --pull always
