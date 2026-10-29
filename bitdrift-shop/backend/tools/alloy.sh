#!/bin/bash
# Sourced by the start scripts, from the backend root. Sets COMPOSE (the compose files to use) and
# DEFAULT_TAG. With GRAFANA_ALLOY_ENABLED=true, set in the environment or in .env, it adds the
# Grafana Alloy overlay (docker-compose.alloy.yml): the :otel image plus a collector that fans out
# to Grafana Cloud, Honeycomb and ClickStack. Off by default.
if [ -z "${GRAFANA_ALLOY_ENABLED:-}" ] && [ -f .env ]; then
  GRAFANA_ALLOY_ENABLED=$(sed -n 's/^GRAFANA_ALLOY_ENABLED=//p' .env | tail -1 | tr -d "\"' \r")
fi
COMPOSE="-f docker-compose.yml"
DEFAULT_TAG=latest
case "${GRAFANA_ALLOY_ENABLED:-false}" in
  true|TRUE|True|1)
    COMPOSE="$COMPOSE -f docker-compose.alloy.yml"
    DEFAULT_TAG=otel
    echo "Grafana Alloy enabled: OpenTelemetry on, exporting via otel-collector (alloy-config.alloy)"
    ;;
esac
