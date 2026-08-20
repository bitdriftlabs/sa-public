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

FAILURES=0

# ID of the workflow the last deploy_workflow call created, so callers can map
# a base name to whatever the platform assigned. Empty when the call failed.
DEPLOYED_ID=""

deploy_workflow() {
  local base="$1" label="$2"
  local wf="workflows/${base}.json"
  local meta="workflows/${base}.metadata.json"
  local chart="workflows/chart-metadata/${base}.chart.json"

  DEPLOYED_ID=""
  [[ -f "$wf" ]] || { echo "  SKIP $label — $wf not found"; FAILURES=$((FAILURES + 1)); return 1; }

  local args=("$wf")
  [[ -f "$meta"  ]] && args+=(--metadata-file "$meta")
  [[ -f "$chart" ]] && args+=(--chart-metadata-file "$chart")

  echo "→ $label"
  local out id
  out="$(bd workflow create "${args[@]}" 2>&1)" || {
    echo "$out" | sed 's/^/    /'; FAILURES=$((FAILURES + 1)); return 1
  }
  # "SUCCESS: Created workflow <ID> - <url>"
  id="$(echo "$out" | sed -n 's/.*Created workflow \([A-Za-z0-9]*\).*/\1/p')"
  [[ -n "$id" ]] || {
    echo "    could not parse workflow id from:"; echo "$out" | sed 's/^/    /'
    FAILURES=$((FAILURES + 1)); return 1
  }
  if bd workflow deploy "$id" >/dev/null 2>&1; then
    echo "    deployed $id"
    DEPLOYED_ID="$id"
  else
    echo "    created $id but DEPLOY FAILED"
    FAILURES=$((FAILURES + 1))
    return 1
  fi
}

# The committed dashboard payload references the workflow IDs of the account it
# was exported from. A fresh account assigns different ones, so each create's ID
# is captured here and substituted into a temporary payload below.
COMMITTED_ID_17=DVE2
COMMITTED_ID_18=55Um
COMMITTED_ID_19=yhl5
NEW_ID_17=""; NEW_ID_18=""; NEW_ID_19=""

echo "Deploying bd-shop iOS workflows…"
deploy_workflow bd-shop-13-ios-app-hang-sessions        "App hang sessions"
deploy_workflow bd-shop-14-ios-paths-to-force-quit      "Paths to force quit"
deploy_workflow bd-shop-15-crashes-by-final-screen      "Crashes by final screen"
deploy_workflow bd-shop-17-ios-journey-vs-crashes       "Journey vs crashes by screen"
NEW_ID_17="$DEPLOYED_ID"
deploy_workflow bd-shop-18-ios-crashes-by-last-screen-live "Crashes by last screen (Ripsaw)"
NEW_ID_18="$DEPLOYED_ID"
deploy_workflow bd-shop-19-ios-crash-terminal-sankey    "Crash-terminal Sankey (needs .activityBased())"
NEW_ID_19="$DEPLOYED_ID"
deploy_workflow bd-shop-20-ios-cold-start-span-timings  "Cold-start span timings"
deploy_workflow bd-shop-21-ios-screen-load-timings      "Screen load timings"
deploy_workflow bd-shop-22-ios-journey-subphase-timings "Journey sub-phase timings"
deploy_workflow bd-shop-23-ios-recommendation-engine-timings "Recommendation engine timings"
deploy_workflow bd-shop-24-ios-persistence-timings      "Persistence I/O timings"

if [[ "$DEPLOY_DASH" -eq 1 ]]; then
  echo
  echo "Deploying dashboard…"
  # `bd dashboard get` does NOT return layout_settings, so the committed payload
  # here is the only complete record of the layout — it is rewritten into a temp
  # file rather than edited in place.
  dash=dashboards/ios-journey-vs-crashes-guided.dashboard.json
  if [[ ! -f "$dash" ]]; then
    echo "    SKIP — $dash not found"
    FAILURES=$((FAILURES + 1))
  elif [[ -z "$NEW_ID_17" || -z "$NEW_ID_18" || -z "$NEW_ID_19" ]]; then
    echo "    SKIP — every chart on the dashboard belongs to bd-shop-17/18/19 and"
    echo "    at least one of them did not deploy, so its charts would point at"
    echo "    workflows that do not exist on this account."
    FAILURES=$((FAILURES + 1))
  else
    tmp="$(mktemp -t bd-shop-dashboard)"
    trap 'rm -f "$tmp"' EXIT
    sed -e "s/\"$COMMITTED_ID_17\"/\"$NEW_ID_17\"/g" \
        -e "s/\"$COMMITTED_ID_18\"/\"$NEW_ID_18\"/g" \
        -e "s/\"$COMMITTED_ID_19\"/\"$NEW_ID_19\"/g" \
        "$dash" > "$tmp"
    echo "    workflow ids: $COMMITTED_ID_17→$NEW_ID_17  $COMMITTED_ID_18→$NEW_ID_18  $COMMITTED_ID_19→$NEW_ID_19"
    out="$(bd dashboard create --request-file "$tmp" -ojson 2>&1)" || {
      echo "$out" | sed 's/^/    /'; FAILURES=$((FAILURES + 1)); out=""
    }
    if [[ -n "$out" ]]; then
      id="$(echo "$out" | sed -n 's/.*"id": *"\([^"]*\)".*/\1/p' | head -1)"
      [[ -n "$id" ]] && echo "    dashboard $id" || {
        echo "    created but could not parse dashboard id"; FAILURES=$((FAILURES + 1))
      }
    fi
  fi
fi

echo
if [[ "$FAILURES" -gt 0 ]]; then
  echo "FAILED — $FAILURES step(s) did not complete. This is a partial deployment."
  exit 1
fi
echo "Done. List what landed with:  bd workflow list"
