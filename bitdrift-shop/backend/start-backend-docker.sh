#!/bin/bash
# Start the backend: pull the published image and run it. The usual entry point.
set -e
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
./tools/ensure-docker.sh
docker compose down
TAG=${1:-latest} docker compose up --pull always
