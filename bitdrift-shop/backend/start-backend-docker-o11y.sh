#!/bin/bash
set -e
"$(dirname "${BASH_SOURCE[0]}")/ensure-docker.sh"
docker compose -f docker-compose.yml -f docker-compose.o11y.yml down
TAG=${1:-latest} docker compose -f docker-compose.yml -f docker-compose.o11y.yml up --pull always
