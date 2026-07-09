#!/bin/bash
# Start the backend with chaos mode — delegates to Docker (matches top-level README)
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/start-backend-chaos-docker.sh" "$@"
