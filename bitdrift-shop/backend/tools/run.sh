#!/bin/bash
# Run the locally built image directly, without compose. Pairs with build.sh.
set -e
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ensure-docker.sh"
# Free port 5173 first
CID=$(docker ps -q --filter "publish=5173")
[ -n "$CID" ] && docker rm -f $CID
docker run --name bitdrift-shop-backend --rm -p 5173:5173 stevelerner/bitdrift-shop-backend:latest
