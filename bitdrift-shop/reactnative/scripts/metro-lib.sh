# Shared Metro bundler helpers for android-3-start-app.sh / ios-3-start-app.sh.
# Extracted from ../start.sh — keep the two in sync if Metro's behavior changes
# there. Callers must set ROOT (the reactnative/ project root) before sourcing.

metro_running() {
  curl -s -m 2 http://localhost:8081/status 2>/dev/null | grep -q "packager-status:running"
}

# /status only proves *a* Metro is up, not that it serves THIS checkout. If another
# RN project already owns 8081, reusing it would silently launch this app against
# that project's bundle. Compare the listening process's working directory to ours.
metro_is_ours() {
  local pid cwd
  pid="$(lsof -ti :8081 -sTCP:LISTEN 2>/dev/null | head -1)"
  [[ -z "$pid" ]] && return 1
  cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
  [[ -n "$cwd" ]] && [[ "$(cd "$cwd" 2>/dev/null && pwd -P)" == "$(cd "$ROOT" && pwd -P)" ]]
}

# Clears Metro's transform cache so react-native-dotenv (@env) is re-evaluated —
# without --reset-cache a stale bundle keeps serving the previous .env values
# (e.g. an old API key).
start_metro_background() {
  if metro_running; then
    if metro_is_ours; then
      echo "Metro already running on port 8081 for this project — restarting with" \
        "--reset-cache so any .env change (e.g. an updated API key) actually takes effect."
      local pid; pid="$(lsof -ti :8081 -sTCP:LISTEN 2>/dev/null | head -1)"
      [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
      for _ in $(seq 1 10); do
        metro_running || break
        sleep 1
      done
    else
      echo "ERROR: Port 8081 is already serving a DIFFERENT React Native project." >&2
      echo "       Owner: $(lsof -a -p "$(lsof -ti :8081 -sTCP:LISTEN | head -1)" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)" >&2
      echo "       This:  $(cd "$ROOT" && pwd -P)" >&2
      echo "       Stop it and re-run:  lsof -ti :8081 | xargs kill" >&2
      exit 1
    fi
  fi
  echo "Starting Metro in the background (log: /tmp/metro-shop-rn.log) ..."
  (cd "$ROOT" && npx react-native start --reset-cache) >/tmp/metro-shop-rn.log 2>&1 &
  for _ in $(seq 1 60); do
    metro_running && break
    sleep 1
  done
  if metro_running; then
    echo "Metro ready on port 8081"
  else
    echo "ERROR: Metro failed to start. Last lines of /tmp/metro-shop-rn.log:" >&2
    tail -20 /tmp/metro-shop-rn.log >&2
    exit 1
  fi
}
