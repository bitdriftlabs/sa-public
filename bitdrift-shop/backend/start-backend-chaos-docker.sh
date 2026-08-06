#!/bin/bash
set -e
"$(dirname "${BASH_SOURCE[0]}")/ensure-docker.sh"
docker compose down
TAG=${1:-latest} CHAOS_MODE=1 docker compose up --pull always
