#!/bin/bash
# Start the backend — delegates to Docker (matches top-level README quick start)
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/start-backend-docker.sh" "$@"
