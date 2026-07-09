#!/bin/bash
set -e
docker network create dd-network 2>/dev/null || true
if docker ps --format '{{.Names}}' | grep -qx dd-agent; then
    docker network connect dd-network dd-agent 2>/dev/null || true
else
    echo "Warning: no running 'dd-agent' container found — traces won't reach Datadog until it's started and connected to the 'dd-network' network." >&2
fi
docker compose down
TAG=${1:-latest} docker compose up --build
