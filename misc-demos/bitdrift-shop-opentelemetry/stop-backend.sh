#!/usr/bin/env bash
# Stop and remove every container this demo starts — the OTel Demo compose stack,
# ClickStack, and Portainer (if present).
#
# This removes containers, not volumes: ClickStack's anonymous `/var/lib/clickhouse`
# volume (and any named volumes the OTel Demo stack owns, e.g. `astronomy-db`) survive
# and get reattached the next time `docker compose up`/`docker run` recreates a
# container with the same name — data is not lost. For a true data reset instead, see
# "Fully purging ClickStack / HyperDX" in APPENDIX.md.
#
# Safe to re-run — does nothing if a given container doesn't exist.
set -euo pipefail

stop_and_remove_by_filter() {
  local label="$1"; shift
  local ids
  ids="$(docker ps -aq "$@")"
  if [[ -n "$ids" ]]; then
    echo "Removing $label: $(docker ps -a --format '{{.Names}}' "$@" | tr '\n' ' ')"
    # shellcheck disable=SC2086
    docker rm -f $ids >/dev/null
  else
    echo "$label: none found"
  fi
}

stop_and_remove_by_filter "OTel Demo stack" --filter "label=com.docker.compose.project=opentelemetry-demo"
# Filtered by exact container name, not image ancestor -- an ancestor filter would stop
# any container on the host running that image, not just this demo's own instance.
stop_and_remove_by_filter "ClickStack" --filter "name=^clickstack$"
stop_and_remove_by_filter "Portainer" --filter "name=^portainer$"

echo "Done. Containers are stopped and removed (volumes kept) — re-run the Quick Start commands to bring them back."
