#!/bin/bash
# Stop the compose stack. Rarely needed — the start scripts run in the
# foreground, so Ctrl-C stops them, and they `docker compose down` on start.
set -e
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker compose down
