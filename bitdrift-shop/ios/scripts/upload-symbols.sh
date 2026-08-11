#!/usr/bin/env bash
# Uploads this build's dSYMs to bitdrift so crash reports come back symbolicated.
# The iOS counterpart of the Android app's `bdUpload*` Gradle tasks.
#
# Run automatically as a post-build phase (see the "Upload bitdrift Symbols"
# phase in the Xcode project), or by hand:
#
#   BITDRIFT_API_KEY=<key> ./scripts/upload-symbols.sh <path-to-dSYMs>
#
# Skips quietly (exit 0) when there is nothing to do — no API key, no dSYM, or a
# Debug build without dSYM generation. A missing symbol upload must never fail
# the build.
set -uo pipefail

log() { echo "note: [bitdrift] $*"; }
warn() { echo "warning: [bitdrift] $*"; }

# ── API key ──────────────────────────────────────────────────────────────
# The same bitdrift API key the app starts the SDK with. Xcode exports build
# settings into script phases, so defining BITDRIFT_API_KEY in .local.xcconfig is
# enough; the environment also works for CI.
API_KEY="${BITDRIFT_API_KEY:-}"
if [[ -z "$API_KEY" ]]; then
  log "BITDRIFT_API_KEY not set — skipping symbol upload."
  log "      Set it in .local.xcconfig or the environment to enable symbolication."
  exit 0
fi

# ── dSYM location ────────────────────────────────────────────────────────
# Xcode exports DWARF_DSYM_FOLDER_PATH during a build phase; allow an explicit
# argument for manual/CI use.
DSYM_DIR="${1:-${DWARF_DSYM_FOLDER_PATH:-}}"
if [[ -z "$DSYM_DIR" || ! -d "$DSYM_DIR" ]]; then
  log "no dSYM directory (${DSYM_DIR:-unset}) — skipping."
  exit 0
fi

shopt -s nullglob
DSYMS=("$DSYM_DIR"/*.dSYM)
shopt -u nullglob
if [[ ${#DSYMS[@]} -eq 0 ]]; then
  # Debug builds default to DEBUG_INFORMATION_FORMAT=dwarf, which emits no dSYM.
  log "no .dSYM bundles in $DSYM_DIR (Debug builds emit none) — skipping."
  exit 0
fi

if ! command -v bd >/dev/null 2>&1; then
  warn "bd CLI not found on PATH — skipping symbol upload."
  warn "        Install it, then re-run: ./scripts/upload-symbols.sh \"$DSYM_DIR\""
  exit 0
fi

# ── Environment ──────────────────────────────────────────────────────────
# BITDRIFT_API_HOST is the SDK's ingest host (api.bitdrift.io); bd wants the base
# domain (bitdrift.io). Derive one from the other so a .dev build uploads to .dev
# rather than silently landing in production.
BASE_DOMAIN_ARGS=()
HOST="${BITDRIFT_API_HOST:-}"
if [[ -n "$HOST" && "$HOST" != "api.bitdrift.io" ]]; then
  BASE_DOMAIN_ARGS=(--base-domain "${HOST#api.}")
  log "uploading to ${HOST#api.}"
fi

# `bd debug-files upload` exits 0 whether or not the upload worked — verified
# against bd 0.2.18, where a bogus API key printed nothing beyond the base domain
# and uploaded nothing, while still exiting 0. The exit code is therefore useless
# here. What it does emit on success is an explicit "File uploaded" line, so key
# off that instead.
uploaded=0
for dsym in "${DSYMS[@]}"; do
  log "submitting $(basename "$dsym")"
  out="$(bd debug-files upload "$dsym" --api-key "$API_KEY" \
          "${BASE_DOMAIN_ARGS[@]+"${BASE_DOMAIN_ARGS[@]}"}" 2>&1)"
  echo "$out" | sed 's/^/note: [bitdrift]   /'
  if echo "$out" | grep -qiE "file uploaded"; then
    uploaded=$((uploaded + 1))
  else
    warn "no upload confirmation for $(basename "$dsym") — check BITDRIFT_API_KEY."
  fi
done

if [[ "$uploaded" -eq ${#DSYMS[@]} ]]; then
  log "uploaded $uploaded/${#DSYMS[@]} dSYM(s)."
else
  warn "uploaded $uploaded/${#DSYMS[@]} dSYM(s) — verify with: bd debug-files list"
fi
# Always exit 0 — a symbolication upload is not worth breaking a build over.
exit 0
