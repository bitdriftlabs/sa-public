# Shared helpers for ios-4-stop-app.sh and ios-foreground-cycle.sh.
#
# Targets either a booted Simulator (via simctl) or a connected physical device
# (via devicectl) behind one set of functions, so the callers don't branch.
#
# Trimmed from ../../ios/scripts/demo-lib.sh (native app): this app has no
# demo-state JSON file or fault-injection watchdog yet, so refresh_state /
# state_value / disarm_flags / drive_pending_watchdog / restart_prefs_daemon
# aren't included. Add them here the same way if RN grows that functionality.

# Must match PRODUCT_BUNDLE_IDENTIFIER in ios/ShopDemoRN.xcodeproj. Unlike the
# native iOS app (bundle id ai.bitdrift.shop.ios), this app is "ai.bitdrift.shop"
# with no .ios suffix — no bundle-id collision with the native app, unlike the
# Android side (see android-1-setup.sh's header comment).
BUNDLE_ID="${BUNDLE_ID:-ai.bitdrift.shop}"

# Set by resolve_target: "sim" or "device", plus the identifier.
TARGET_KIND=""
TARGET_ID=""

booted_simulator() {
  xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F-]{36}' | head -1
}

connected_device() {
  # The State column wording varies — "connected" when actively attached,
  # "available (paired)" when known but idle — so match either rather than the
  # literal "connected", and skip the header and separator rows.
  xcrun devicectl list devices 2>/dev/null \
    | awk '$0 !~ /^(Name|-+[[:space:]])/ && /connected|available/ {
             for (i=1;i<=NF;i++)
              if ($i ~ /^([0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16})$/) { print $i; exit }
           }'
}

# resolve_target <kind|auto> <id|"">
# kind: sim | device | auto
resolve_target() {
  local kind="${1:-auto}" id="${2:-}"
  # "ambiguous" when both targets are live, "none" when neither is. Callers use
  # this to avoid printing a "boot a simulator" hint at someone who has two.
  RESOLVE_ERROR="none"

  case "$kind" in
    sim)
      TARGET_KIND="sim"
      TARGET_ID="${id:-$(booted_simulator)}"
      ;;
    device)
      TARGET_KIND="device"
      TARGET_ID="${id:-$(connected_device)}"
      ;;
    auto)
      # Refuse to guess when both are live. Silently preferring one meant a bare
      # invocation could sit watching an idle Simulator while the phone you were
      # actually testing waited.
      local sim dev; sim="$(booted_simulator)"; dev="$(connected_device)"
      if [[ -n "$sim" && -n "$dev" ]]; then
        RESOLVE_ERROR="ambiguous"
        echo "Both a booted simulator and a connected device are available:" >&2
        echo "  --simulator $sim" >&2
        echo "  --device    $dev" >&2
        echo "Pass one explicitly." >&2
        return 1
      elif [[ -n "$sim" ]]; then
        TARGET_KIND="sim"; TARGET_ID="$sim"
      else
        TARGET_KIND="device"; TARGET_ID="$dev"
      fi
      ;;
  esac

  [[ -n "$TARGET_ID" ]]
}

target_label() {
  echo "$TARGET_KIND $TARGET_ID"
}

app_installed() {
  case "$TARGET_KIND" in
    sim) [[ -n "$(xcrun simctl get_app_container "$TARGET_ID" "$BUNDLE_ID" data 2>/dev/null)" ]] ;;
    device)
      xcrun devicectl device info apps --device "$TARGET_ID" 2>/dev/null | grep -q "$BUNDLE_ID"
      ;;
  esac
}

app_pid() {
  case "$TARGET_KIND" in
    sim)
      xcrun simctl spawn "$TARGET_ID" launchctl list 2>/dev/null \
        | awk -v id="$BUNDLE_ID" '$3 ~ id && $1 ~ /^[0-9]+$/ { print $1; exit }'
      ;;
    device)
      # Matching on the executable name alone (as before) can return the
      # wrong app's PID: BitdriftShop.app/BitdriftShop is the product name
      # shared with the native iOS app's PRODUCT_NAME too (see
      # ../../ios/scripts/demo-lib.sh), so if both are installed and running
      # on the same physical device this would silently pick either one.
      # Resolve this bundle's on-device container path instead (it embeds a
      # per-install UUID that can't collide with another app's) and only
      # match a process whose executable path carries that same UUID.
      bundle_process_pid "$TARGET_ID" "$BUNDLE_ID"
      ;;
  esac
}

# Prints the PID of the process belonging to $2 (a bundle ID) on device $1, by
# cross-referencing `device info apps --bundle-id` (this app's on-device
# container path, which embeds a per-install UUID) against `device info
# processes` (which only exposes an executable path, not a bundle ID) —
# scanned generically over whatever JSON fields devicectl reports, since the
# exact field names aren't documented and shouldn't be assumed stable across
# devicectl versions.
bundle_process_pid() {
  local device="$1" bundle_id="$2" apps_json procs_json
  apps_json="$(mktemp)"; procs_json="$(mktemp)"
  xcrun devicectl device info apps --device "$device" --bundle-id "$bundle_id" \
    --include-container-paths --json-output "$apps_json" >/dev/null 2>&1
  xcrun devicectl device info processes --device "$device" \
    --json-output "$procs_json" >/dev/null 2>&1
  python3 - "$apps_json" "$procs_json" <<'PY'
import json, re, sys

UUID_RE = re.compile(r'[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}')

def strings(obj):
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for v in obj.values():
            yield from strings(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from strings(v)

def find_list(obj):
    if isinstance(obj, dict):
        for v in obj.values():
            if isinstance(v, list) and v and isinstance(v[0], dict):
                return v
            found = find_list(v)
            if found is not None:
                return found
    return None

try:
    apps = find_list(json.load(open(sys.argv[1]))) or []
    procs = find_list(json.load(open(sys.argv[2]))) or []
except Exception:
    sys.exit(1)

if not apps:
    sys.exit(1)

app_uuids = set()
for s in strings(apps[0]):
    app_uuids.update(UUID_RE.findall(s))
if not app_uuids:
    sys.exit(1)

for proc in procs:
    proc_uuids = set()
    for s in strings(proc):
        proc_uuids.update(UUID_RE.findall(s))
    if app_uuids & proc_uuids:
        pid = proc.get("pid") or proc.get("processIdentifier") or proc.get("processID")
        if pid is not None:
            print(pid)
            sys.exit(0)

sys.exit(1)
PY
  local status=$?
  rm -f "$apps_json" "$procs_json"
  return $status
}

# Launches, then confirms the process actually came up (simctl/devicectl both
# exit 0 even when the launch silently no-ops, e.g. simctl against a booting-
# but-not-yet-ready Simulator) and retries once rather than assuming success.
launch_app() {
  local out attempt
  for attempt in 1 2; do
    case "$TARGET_KIND" in
      sim) out="$(xcrun simctl launch "$TARGET_ID" "$BUNDLE_ID" 2>&1)" || true ;;
      device) out="$(xcrun devicectl device process launch --device "$TARGET_ID" "$BUNDLE_ID" 2>&1)" || true ;;
    esac
    [[ -n "$(app_pid)" ]] && return 0
    echo "warning: launch_app attempt $attempt did not produce a running process: $out" >&2
    sleep 1
  done
  return 1
}

terminate_app() {
  case "$TARGET_KIND" in
    sim) xcrun simctl terminate "$TARGET_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true ;;
    device)
      local pid; pid="$(app_pid)"
      [[ -n "$pid" ]] && xcrun devicectl device process terminate \
        --device "$TARGET_ID" --pid "$pid" >/dev/null 2>&1 || true
      ;;
  esac
}

# Sends the app to the background so a background-half demo can run.
#
# Neither platform lets the app background itself, so this is done from outside
# by giving something else the foreground:
#   - Simulator: launching SpringBoard returns to the home screen.
#   - Device: there is no SpringBoard equivalent over devicectl, but launching
#     any other app has the same effect. Settings is used because it is present
#     on every device, harmless to open, and cheap to launch.
#
# There's no CLI-visible "is X frontmost" signal on either target (unlike
# Android's dumpsys), so unlike launch_app this can't verify the transition
# actually happened — it can only stop swallowing errors and retry once on a
# reported failure instead of assuming success.
background_app() {
  local out attempt
  for attempt in 1 2; do
    case "$TARGET_KIND" in
      sim) out="$(xcrun simctl launch "$TARGET_ID" com.apple.springboard 2>&1)" && return 0 ;;
      device) out="$(xcrun devicectl device process launch --device "$TARGET_ID" com.apple.Preferences 2>&1)" && return 0 ;;
    esac
    echo "warning: background_app attempt $attempt failed: $out" >&2
    sleep 1
  done
  return 1
}

# Parses the shared --simulator/--device flags out of "$@".
# Sets PARSED_KIND, PARSED_ID, and PARSED_REST (remaining args).
#
# Must be called directly, never via $(...) — command substitution would run it
# in a subshell and none of these assignments would reach the caller.
parse_target_flags() {
  PARSED_KIND="auto"; PARSED_ID=""; PARSED_REST=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --simulator)
        PARSED_KIND="sim"
        if [[ -n "${2:-}" && "${2:-}" != -* ]]; then PARSED_ID="$2"; shift; fi
        shift ;;
      --device)
        PARSED_KIND="device"
        if [[ -n "${2:-}" && "${2:-}" != -* ]]; then PARSED_ID="$2"; shift; fi
        shift ;;
      *) PARSED_REST+=("$1"); shift ;;
    esac
  done
}
