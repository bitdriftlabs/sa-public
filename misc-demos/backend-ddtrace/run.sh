#!/bin/bash
set -e
# Clear port 5173 first
CID=$(docker ps -q --filter "publish=5173")
[ -n "$CID" ] && docker rm -f $CID
docker network create dd-network 2>/dev/null || true
docker network connect dd-network dd-agent 2>/dev/null || true
docker run --name bitdrift-shop-backend --rm -p 5173:5173 --network dd-network stevelerner/bitdrift-shop-backend:latest
