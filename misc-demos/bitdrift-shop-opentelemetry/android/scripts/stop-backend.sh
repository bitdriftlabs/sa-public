#!/usr/bin/env bash
# Stop every container this demo starts — the OTel Demo compose stack,
# ClickStack, and Portainer (if running) — without removing them.
#
# Why this matters: the OTel Demo stack's services all use `restart:
# unless-stopped`, so a plain `colima stop && colima start` (or a Docker
# daemon restart) brings them all back automatically. Docker only honors
# that policy until a container is *explicitly* stopped — after that it
# stays down across daemon/VM restarts until you `up`/`start` it again.
# ClickStack and Portainer don't set a restart policy at all (Docker's
# default is "no"), so they're included here for a complete cleanup, not
# because they'd otherwise come back on their own.
#
# Safe to re-run — does nothing if a given container isn't running. This
# does NOT remove containers or volumes, so `docker compose up -d` (or
# `docker start <container>`) picks up right where you left off. For a
# destructive full reset instead, see APPENDIX.md.
set -euo pipefail

stop_by_filter() {
  local label="$1"; shift
  local ids
  ids="$(docker ps -q "$@")"
  if [[ -n "$ids" ]]; then
    echo "Stopping $label: $(docker ps --format '{{.Names}}' "$@" | tr '\n' ' ')"
    # shellcheck disable=SC2086
    docker stop $ids >/dev/null
  else
    echo "$label: none running"
  fi
}

stop_by_filter "OTel Demo stack" --filter "label=com.docker.compose.project=opentelemetry-demo"
# Filtered by exact container name, not image ancestor -- an ancestor filter would stop
# any container on the host running that image, not just this demo's own instance.
stop_by_filter "ClickStack" --filter "name=^clickstack$"
stop_by_filter "Portainer" --filter "name=^portainer$"

echo "Done. Containers are stopped, not removed — 'docker start <name>' or re-running the Quick Start commands brings them back."
