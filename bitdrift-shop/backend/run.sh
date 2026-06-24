#!/bin/bash
set -e
# Clear port 5173 first
CID=$(docker ps -q --filter "publish=5173")
[ -n "$CID" ] && docker rm -f $CID
docker run --name bitdrift-shop-backend --rm -p 5173:5173 stevelerner/bitdrift-shop-backend:latest
