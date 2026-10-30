#!/usr/bin/env bash
# Publish the two metric workflows (workflows/otel-api-metrics.json, otel-journey-health.json)
# and the "Telescope Store" dashboard (dashboards/otel-telescope-store.dashboard.json).
#
# Idempotent: existing workflows are reconciled with the committed files (stopped first if LIVE,
# since logic can't be edited while LIVE) and redeployed; an existing dashboard is replaced.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DASHBOARD_FILE="$ROOT/dashboards/otel-telescope-store.dashboard.json"

if ! command -v bd >/dev/null 2>&1; then
  echo "ERROR: bd CLI not found. Install it: https://github.com/bitdriftlabs/bd-cli-releases" >&2
  exit 1
fi
if ! bd auth --status -ojson 2>/dev/null | grep -q '"authenticated":true'; then
  echo "Not authenticated — running 'bd auth' ..."
  bd auth
fi

# deploy_workflow <file-base> -> echoes the workflow id
deploy_workflow() {
  # Command substitution doesn't inherit errexit, so enable it here: a failed update must abort the
  # script before the (already-stale) workflow is redeployed and the dashboard replaced.
  set -e
  local base="$1" file meta chart name id state
  file="$ROOT/workflows/$base.json"
  meta="$ROOT/workflows/$base.metadata.json"
  chart="$ROOT/workflows/chart-metadata/$base.chart.json"
  name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$file")"
  id="$(bd workflow list --workflow-name "$name" -ojson --jq "[.items[] | select(.workflow.name == \"$name\")] | first | .workflow.id // empty" -r)"
  if [[ -n "$id" ]]; then
    state="$(bd workflow list --workflow-id "$id" -ojson --jq '.items[0].workflow.state' -r)"
    echo "Workflow $id exists ($state) — reconciling $base ..." >&2
    [[ "$state" == "LIVE" ]] && bd workflow stop "$id" >&2
    bd workflow update --workflow-id "$id" --workflow-file "$file" --metadata-file "$meta" --chart-metadata-file "$chart" >&2
    bd workflow deploy "$id" >&2
  else
    echo "Creating $base ..." >&2
    bd workflow create "$file" --metadata-file "$meta" --chart-metadata-file "$chart" --deploy >&2
    id="$(bd workflow list --workflow-name "$name" -ojson --jq "[.items[] | select(.workflow.name == \"$name\")] | first | .workflow.id" -r)"
  fi
  echo "$id"
}

API_ID="$(deploy_workflow otel-api-metrics)"
JOURNEY_ID="$(deploy_workflow otel-journey-health)"
echo "Workflows: api=$API_ID journey=$JOURNEY_ID"

# Dashboards reference workflows by ID, so substitute the real IDs for the placeholders.
REQUEST="$(mktemp)"
trap 'rm -f "$REQUEST"' EXIT
sed -e "s/__OTEL_API_METRICS_WORKFLOW_ID__/$API_ID/g" -e "s/__OTEL_JOURNEY_HEALTH_WORKFLOW_ID__/$JOURNEY_ID/g" "$DASHBOARD_FILE" > "$REQUEST"

DASH_NAME="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$DASHBOARD_FILE")"
DASH_ID="$(bd dashboard list --query "$DASH_NAME" -ojson --jq "[.dashboards[].custom_dashboard | select(.title == \"$DASH_NAME\")] | first | .id // empty" -r)"
# An in-place update needs the server's numeric chart row IDs, so replace the dashboard instead.
if [[ -n "$DASH_ID" ]]; then
  echo "Replacing existing dashboard $DASH_ID ..."
  bd dashboard delete "$DASH_ID" >/dev/null
fi
DASH_ID="$(bd dashboard create --request-file "$REQUEST" -ojson --jq '.dashboard.id' -r)"
echo "Dashboard: $DASH_ID"
