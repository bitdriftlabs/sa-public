#!/usr/bin/env bash
# Stop and remove every container this demo starts — the OTel Demo compose stack,
# ClickStack, and Portainer (if present).
#
# This does NOT delete data for the OTel Demo stack's own named volumes (e.g.
# `astronomy-db`) -- those are recreated and reattached correctly next time
# `docker compose up` brings the service back, same container/volume names both times.
#
# ClickStack is different and this is a real, one-way data loss: the Quick Start's
# `docker run` for it (deliberately, see README.md#1-set-up-clickstack) has no `-v`, so
# its `/var/lib/clickhouse` volume is anonymous. Removing that container here orphans
# that volume for good -- Docker has no way to reattach an anonymous volume to a
# differently-created container later, even with the same name. The *next* ClickStack
# container this script's removal leads to will start with an empty database: you'll
# need to sign up again and get a new ingestion API key (same end state as "Fully
# purging ClickStack / HyperDX" in APPENDIX.md, just reached as a side effect instead
# of on purpose). If you want ClickStack's trace/log history to survive this script,
# add a named volume (`-v clickstack-data:/var/lib/clickhouse`) to that `docker run`
# command before the first time you run it.
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

echo "Done. Containers are stopped and removed — re-run the Quick Start commands to bring them back."
echo "Note: ClickStack's trace/log history does not survive this (anonymous volume, orphaned on removal) —"
echo "you'll sign up again and get a new ingestion API key next time it starts."
