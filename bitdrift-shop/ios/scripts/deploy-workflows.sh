#!/usr/bin/env bash
# Creates and deploys every bd-shop iOS workflow, then the dashboard that
# composes them. Idempotent only in the sense that re-running creates NEW
# workflows — the platform assigns IDs on create, so this is for standing a
# fresh account up, not for reconciling an existing one.
#
#   ./scripts/deploy-workflows.sh              # all workflows + dashboard
#   ./scripts/deploy-workflows.sh --no-dash    # workflows only
#
# To update an already-deployed workflow instead, note its ID and use:
#   bd workflow stop <id>
#   bd workflow update --workflow-id <id> --workflow-file <f> \
#       --metadata-file <m> --chart-metadata-file <c>
#   bd workflow deploy <id>
#
# The stop/update/deploy dance is required because a deployed workflow's config
# is locked. Metadata-only changes (titles, descriptions, chart display mode)
# are the exception — those apply to a LIVE workflow without a stop, and
# without resetting its evaluation window. Prefer that when you can: a
# stop/deploy cycle means the workflow only sees sessions starting after the
# redeploy, so any accumulated data is effectively discarded.
#
# Note also that multi-entry chart-metadata files MUST be sent alongside
# --workflow-file; the API rejects them on their own ("must contain exactly one
# item when workflow_file is omitted").
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DEPLOY_DASH=1
[[ "${1:-}" == "--no-dash" ]] && DEPLOY_DASH=0

command -v bd >/dev/null || { echo "bd CLI not found — brew install bitdriftlabs/bd/bd" >&2; exit 1; }
bd auth --status >/dev/null 2>&1 || { echo "not authenticated — run: bd auth" >&2; exit 1; }

deploy_workflow() {
  local base="$1" label="$2"
  local wf="workflows/${base}.json"
  local meta="workflows/${base}.metadata.json"
  local chart="workflows/chart-metadata/${base}.chart.json"

  [[ -f "$wf" ]] || { echo "  SKIP $label — $wf not found"; return; }

  local args=("$wf")
  [[ -f "$meta"  ]] && args+=(--metadata-file "$meta")
  [[ -f "$chart" ]] && args+=(--chart-metadata-file "$chart")

  echo "→ $label"
  local out id
  out="$(bd workflow create "${args[@]}" 2>&1)" || { echo "$out" | sed 's/^/    /'; return 1; }
  # "SUCCESS: Created workflow <ID> - <url>"
  id="$(echo "$out" | sed -n 's/.*Created workflow \([A-Za-z0-9]*\).*/\1/p')"
  [[ -n "$id" ]] || { echo "    could not parse workflow id from:"; echo "$out" | sed 's/^/    /'; return 1; }
  bd workflow deploy "$id" >/dev/null 2>&1 && echo "    deployed $id" || echo "    created $id but DEPLOY FAILED"
}

echo "Deploying bd-shop iOS workflows…"
deploy_workflow bd-shop-13-ios-app-hang-sessions        "App hang sessions"
deploy_workflow bd-shop-14-ios-paths-to-force-quit      "Paths to force quit"
deploy_workflow bd-shop-15-crashes-by-final-screen      "Crashes by final screen"
deploy_workflow bd-shop-17-ios-journey-vs-crashes       "Journey vs crashes by screen"
deploy_workflow bd-shop-18-ios-crashes-by-last-screen-live "Crashes by last screen (Ripsaw)"
deploy_workflow bd-shop-19-ios-crash-terminal-sankey    "Crash-terminal Sankey (needs .activityBased())"

if [[ "$DEPLOY_DASH" -eq 1 ]]; then
  echo
  echo "Deploying dashboard…"
  # The dashboard payload references workflow IDs (DVE2 / 55Um) inline. On a
  # fresh account those IDs differ, so point its chart_id.workflow_id values at
  # the IDs printed above before running this, or create the dashboard in the UI
  # and re-export. `bd dashboard get` does NOT return layout_settings, so the
  # committed payload here is the only complete record of the layout.
  if [[ -f dashboards/ios-journey-vs-crashes-guided.dashboard.json ]]; then
    bd dashboard create --request-file dashboards/ios-journey-vs-crashes-guided.dashboard.json \
      -ojson 2>&1 | sed -n 's/.*"id": *"\([^"]*\)".*/    dashboard \1/p' | head -1
  else
    echo "    SKIP — dashboards/ios-journey-vs-crashes-guided.dashboard.json not found"
  fi
fi

echo
echo "Done. List what landed with:  bd workflow list"
