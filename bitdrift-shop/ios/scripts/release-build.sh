#!/usr/bin/env bash
# Release build — the configuration that produces dSYMs and uploads them to
# bitdrift for crash symbolication.
#
# Debug builds emit no dSYM (DEBUG_INFORMATION_FORMAT = dwarf), so symbolicated
# crash reports only ever come from a Release build.
#
#   ./scripts/release-build.sh                     # auto target, build only
#   ./scripts/release-build.sh --simulator         # Release for the Simulator (no signing)
#   ./scripts/release-build.sh --device            # Release for the connected device
#   ./scripts/release-build.sh --device --install   # ...and install it
#   ./scripts/release-build.sh --team ABCDE12345   # override the signing team
#
# Verifies the symbol upload actually landed by counting debug files before and
# after — `bd debug-files upload` exits 0 even when the API key is rejected, so
# its own output cannot be trusted for that.
set -uo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=demo-lib.sh
source "scripts/demo-lib.sh"

PROJECT="BitdriftShop.xcodeproj"
SCHEME="BitdriftShop"
DERIVED="build/release"
TEAM=""
INSTALL=0

parse_target_flags "$@"
set -- ${PARSED_REST[@]+"${PARSED_REST[@]}"}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --team) TEAM="${2:-}"; shift 2 ;;
    --install) INSTALL=1; shift ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if ! resolve_target "$PARSED_KIND" "$PARSED_ID"; then
  # resolve_target already explained itself when the choice was ambiguous.
  if [[ "${RESOLVE_ERROR:-none}" == "none" ]]; then
    echo "No target found. Boot a simulator, or connect a device and pass --device." >&2
  fi
  exit 1
fi

# ── Preflight: the API key is the whole point of a Release build here ─────
API_KEY_PRESENT=0
if [[ -n "${BITDRIFT_API_KEY:-}" ]]; then
  API_KEY_PRESENT=1
elif xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
       -showBuildSettings 2>/dev/null | grep -qE "^\s+BITDRIFT_API_KEY = .+"; then
  API_KEY_PRESENT=1
fi

if [[ "$API_KEY_PRESENT" -eq 0 ]]; then
  echo "WARNING: BITDRIFT_API_KEY is not set — the build will succeed but dSYMs"
  echo "         will NOT be uploaded, so crashes stay unsymbolicated."
  echo "         Add it to .local.xcconfig:  BITDRIFT_API_KEY = <platform-api-key>"
  echo
fi

# ── Destination + signing ────────────────────────────────────────────────
DEST_ARGS=()
EXTRA_ARGS=()
case "$TARGET_KIND" in
  sim)
    DEST_ARGS=(-destination "id=$TARGET_ID")
    ;;
  device)
    DEST_ARGS=(-destination "id=$TARGET_ID" -allowProvisioningUpdates)
    # Signing a device build needs a team. Prefer an explicit --team, else pick up
    # DEVELOPMENT_TEAM if it is already set in .local.xcconfig / the environment.
    if [[ -z "$TEAM" ]]; then
      TEAM="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
                -showBuildSettings 2>/dev/null \
                | awk '/^[[:space:]]+DEVELOPMENT_TEAM = /{print $3; exit}')"
    fi
    if [[ -z "$TEAM" ]]; then
      echo "A device build needs a signing team. Either:" >&2
      echo "  ./scripts/release-build.sh --device --team <TEAM_ID>" >&2
      echo "  or add 'DEVELOPMENT_TEAM = <TEAM_ID>' to .local.xcconfig" >&2
      echo "Find it at developer.apple.com -> Account -> Membership details." >&2
      exit 1
    fi
    EXTRA_ARGS=("DEVELOPMENT_TEAM=$TEAM")
    ;;
esac

# `bd debug-files list` prints its "INFO: returned=N total=N" summary on stderr,
# not stdout — so this has to merge them. Discarding stderr silently yields an
# empty count and makes the verification below look like it could not run.
debug_file_count() {
  bd debug-files list 2>&1 | grep -oE 'total=[0-9]+' | head -1 | cut -d= -f2
}

HAVE_BD=0
BEFORE=""
if command -v bd >/dev/null 2>&1; then
  HAVE_BD=1
  BEFORE="$(debug_file_count)"
fi

echo "Release build for $(target_label)${TEAM:+ (team $TEAM)}"
rm -rf "$DERIVED"

xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  "${DEST_ARGS[@]}" "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}" \
  -derivedDataPath "$DERIVED" build 2>&1 \
  | grep -E "error:|\[bitdrift\]|BUILD (SUCCEEDED|FAILED)"
BUILD_STATUS=${PIPESTATUS[0]}

if [[ "$BUILD_STATUS" -ne 0 ]]; then
  echo "Build failed." >&2
  exit "$BUILD_STATUS"
fi

APP="$(find "$DERIVED/Build/Products" -maxdepth 2 -name "$SCHEME.app" | head -1)"
DSYM="$(find "$DERIVED/Build/Products" -maxdepth 2 -name "$SCHEME.app.dSYM" | head -1)"
echo
echo "app:  ${APP:-not found}"
echo "dSYM: ${DSYM:-not found}"

# ── Upload reporting ────────────────────────────────────────────────────
#
# Deliberately NOT a pass/fail check on the debug-file count. An unchanged count
# does not mean failure: rebuilding unchanged source produces the same dSYM UUID,
# which the platform deduplicates, so a perfectly successful upload leaves the
# total flat. The reverse is true too — an unrelated concurrent upload can raise
# it. `bd debug-files list` exposes only a content hash, not the dSYM UUID, so the
# listing cannot be matched against this build either.
#
# The authoritative signal is the build phase above: upload-symbols.sh keys off
# bd's explicit "File uploaded" line and warns per-dSYM when it is absent. The
# count is printed here only as context.
if [[ "$HAVE_BD" -eq 1 && -n "$BEFORE" ]]; then
  AFTER="$(debug_file_count)"
  if [[ "$AFTER" == "$BEFORE" ]]; then
    echo "debug files on the platform: ${AFTER} (unchanged — same dSYM UUID is deduplicated)"
  else
    echo "debug files on the platform: ${BEFORE} -> ${AFTER} (new dSYM stored)"
  fi
  echo "See the [bitdrift] lines above for whether this build's upload was accepted."
else
  echo "bd CLI not on PATH — no upload reporting."
fi

# ── Optional install ────────────────────────────────────────────────────
if [[ "$INSTALL" -eq 1 && -n "$APP" ]]; then
  echo
  echo "Installing to $(target_label)…"
  case "$TARGET_KIND" in
    sim) xcrun simctl install "$TARGET_ID" "$APP" && echo "Installed." ;;
    device) xcrun devicectl device install app --device "$TARGET_ID" "$APP" >/dev/null \
              && echo "Installed." || echo "Install failed." ;;
  esac
fi
