#!/bin/bash
# Stop any container using port 5173
CID=$(docker ps -q --filter "publish=5173")
[ -n "$CID" ] && docker rm -f $CID
docker rm -f bitdrift-shop-backend 2>/dev/null || true
echo "Done"
