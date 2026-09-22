#!/usr/bin/env bash
# Publish the "Capture All Sessions" workflow (workflows/capture-all-sessions.json) so every
# session of this demo app is guaranteed to land a full timeline — run this before a live demo,
# not mid-demo, since a capture workflow only sees sessions that start *after* it deploys.
#
# Idempotent: if a workflow with this name already exists, reuses it (deploying it if it's
# sitting IDLE) instead of creating a duplicate.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW_NAME="bitdrift-shop-opentelemetry — Capture All Sessions (Demo)"
WORKFLOW_FILE="$ROOT/workflows/capture-all-sessions.json"
METADATA_FILE="$ROOT/workflows/capture-all-sessions.metadata.json"

if ! command -v bd >/dev/null 2>&1; then
  echo "ERROR: bd CLI not found. Install it: https://github.com/bitdriftlabs/bd-cli-releases" >&2
  exit 1
fi

if ! bd auth --status -ojson 2>/dev/null | grep -q '"authenticated":true'; then
  echo "Not authenticated — running 'bd auth' ..."
  bd auth
fi

EXISTING="$(bd workflow list -ojson --jq "[.items[] | select(.workflow.name == \"$WORKFLOW_NAME\")] | first // empty" 2>/dev/null)"

if [[ -n "$EXISTING" && "$EXISTING" != "null" ]]; then
  ID="$(echo "$EXISTING" | python3 -c 'import json,sys; print(json.load(sys.stdin)["workflow"]["id"])')"
  STATE="$(echo "$EXISTING" | python3 -c 'import json,sys; print(json.load(sys.stdin)["workflow"]["state"])')"
  # Always reconcile rather than trusting STATE alone — a LIVE workflow could
  # have drifted from the committed files (edited in the UI, or from an older
  # version of this repo), and "already LIVE" would then report success while
  # the server keeps running stale rules. Workflow logic can't be edited
  # while LIVE, so stop it first if needed.
  echo "Workflow $ID exists ($STATE) — reconciling with $WORKFLOW_FILE ..."
  [[ "$STATE" == "LIVE" ]] && bd workflow stop "$ID"
  bd workflow update --workflow-id "$ID" --workflow-file "$WORKFLOW_FILE" --metadata-file "$METADATA_FILE"
  bd workflow deploy "$ID"
else
  echo "Creating and deploying workflow from $WORKFLOW_FILE ..."
  ID="$(bd workflow create "$WORKFLOW_FILE" --metadata-file "$METADATA_FILE" --deploy -ojson --jq '.id' -r)"
fi

echo "Workflow: $ID ($WORKFLOW_NAME)"
bd workflow open "$ID" -ojson --jq '.url' -r
