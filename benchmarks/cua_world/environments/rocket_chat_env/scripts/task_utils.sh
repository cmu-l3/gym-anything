#!/bin/bash
# Shared task setup utilities for Rocket.Chat tasks.

set -euo pipefail

ROCKETCHAT_BASE_URL="http://localhost:3000"
ROCKETCHAT_LOGIN_URL="${ROCKETCHAT_BASE_URL}/login"
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
FIREFOX_RUNTIME_PROFILE_DIR="/home/ga/.mozilla/firefox/runtime.profile"
FIREFOX_LOG_FILE="/tmp/firefox_rocketchat_task.log"
SEED_MANIFEST_FILE="/tmp/rocket_chat_seed_manifest.json"
ROCKETCHAT_TASK_USERNAME="admin"
ROCKETCHAT_TASK_PASSWORD="Admin1234!"

log() {
  echo "[rocket_chat_task] $*"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

wait_for_http() {
  local url="$1"
  local timeout_sec="${2:-600}"
  local elapsed=0

  log "Waiting for HTTP readiness: $url"

  while [ "$elapsed" -lt "$timeout_sec" ]; do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    if [ "$code" = "200" ] || [ "$code" = "401" ] || [ "$code" = "403" ]; then
      log "HTTP ready after ${elapsed}s (HTTP $code)"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  log "ERROR: Timeout waiting for HTTP readiness: $url"
  return 1
}

wait_for_window() {
  local window_pattern="$1"
  local timeout="${2:-30}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout" ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then
      return 0
    fi
    sleep 0.5
    elapsed=$((elapsed + 1))
  done

  return 1
}

has_close_firefox_dialog() {
  DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Close Firefox"
}

dismiss_close_firefox_dialog() {
  local dialog_id
  dialog_id=$(DISPLAY=:1 wmctrl -l 2>/dev/null | awk 'tolower($0) ~ /close firefox/ {print $1; exit}')
  if [ -n "$dialog_id" ]; then
    focus_window "$dialog_id" || true
    # Activate default "Close Firefox" action to clear stale profile lock prompts.
    DISPLAY=:1 xdotool key --clearmodifiers Return 2>/dev/null || true
    sleep 1
  fi
}

get_firefox_window_id() {
  DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'epiphany\|web\|firefox\|mozilla\|rocket.chat' | grep -vi 'close firefox' | awk '{print $1; exit}'
}

focus_window() {
  local window_id="$1"
  DISPLAY=:1 wmctrl -ia "$window_id" 2>/dev/null || DISPLAY=:1 wmctrl -a "$window_id" 2>/dev/null || return 1
  sleep 0.3
  return 0
}

maximize_active_window() {
  DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
}

focus_firefox() {
  local wid
  wid=$(get_firefox_window_id)
  if [ -n "$wid" ]; then
    focus_window "$wid" || true
    maximize_active_window
    return 0
  fi
  return 1
}

take_screenshot() {
  local output_file="${1:-/tmp/screenshot.png}"
  DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
}

stop_firefox() {
  pkill -TERM -f 'firefox|epiphany' 2>/dev/null || true

  for _ in {1..40}; do
    if pgrep -f 'firefox|epiphany' >/dev/null 2>&1; then
      sleep 0.5
    else
      break
    fi
  done

  if pgrep -f 'firefox|epiphany' >/dev/null 2>&1; then
    pkill -KILL -f 'firefox|epiphany' 2>/dev/null || true
    sleep 1
  fi
}

clear_firefox_profile_locks() {
  local profile_dir="${1:-$FIREFOX_PROFILE_DIR}"
  rm -rf \
    "$profile_dir/lock" \
    "$profile_dir/.parentlock" \
    "$profile_dir/parent.lock" \
    "$profile_dir/singletonLock" \
    "$profile_dir/singletonCookie" \
    "$profile_dir/singletonSocket" \
    2>/dev/null || true
}

prepare_firefox_runtime_profile() {
  rm -rf "$FIREFOX_RUNTIME_PROFILE_DIR" 2>/dev/null || true
  mkdir -p "$FIREFOX_RUNTIME_PROFILE_DIR"

  if [ -d "$FIREFOX_PROFILE_DIR" ]; then
    cp -a "$FIREFOX_PROFILE_DIR/." "$FIREFOX_RUNTIME_PROFILE_DIR/" 2>/dev/null || true
  fi

  if [ ! -f "$FIREFOX_RUNTIME_PROFILE_DIR/user.js" ]; then
    cat > "$FIREFOX_RUNTIME_PROFILE_DIR/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
USERJS
  fi

  chown -R ga:ga "$FIREFOX_RUNTIME_PROFILE_DIR" 2>/dev/null || true
  clear_firefox_profile_locks "$FIREFOX_RUNTIME_PROFILE_DIR"
}

navigate_to_url() {
  local url="$1"

  if ! has_command xdotool; then
    return 0
  fi

  DISPLAY=:1 xdotool key --clearmodifiers ctrl+l 2>/dev/null || true
  sleep 0.2
  DISPLAY=:1 xdotool type --delay 15 --clearmodifiers "$url" 2>/dev/null || true
  DISPLAY=:1 xdotool key --clearmodifiers Return 2>/dev/null || true
}

wait_for_firefox_main_window() {
  local timeout_sec="${1:-30}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout_sec" ]; do
    if has_close_firefox_dialog; then
      dismiss_close_firefox_dialog
    fi

    local wid
    wid=$(get_firefox_window_id)
    if [ -n "$wid" ]; then
      echo "$wid"
      return 0
    fi

    sleep 0.5
    elapsed=$((elapsed + 1))
  done

  return 1
}

restart_firefox() {
  local url="$1"
  local attempts="${2:-3}"
  local browser_cmd=""

  # Wait for Rocket.Chat web service to be ready before launching browser
  wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 120 || log "WARNING: Rocket.Chat may not be ready, attempting browser launch anyway"

  if has_command epiphany-browser; then
    browser_cmd="epiphany-browser"
  elif has_command epiphany; then
    browser_cmd="epiphany"
  else
    browser_cmd="firefox"
  fi

  for attempt in $(seq 1 "$attempts"); do
    log "Starting browser (attempt ${attempt}/${attempts}): $url"

    stop_firefox
    clear_firefox_profile_locks
    rm -f "$FIREFOX_LOG_FILE" 2>/dev/null || true

    if [ "$browser_cmd" = "firefox" ]; then
      su - ga -c "DISPLAY=:1 dbus-launch --exit-with-session firefox --no-remote --new-instance '$url' > '$FIREFOX_LOG_FILE' 2>&1 &"
    else
      su - ga -c "DISPLAY=:1 $browser_cmd '$url' > '$FIREFOX_LOG_FILE' 2>&1 &"
    fi

    local wid=""
    if wid=$(wait_for_firefox_main_window 80); then
      focus_window "$wid" || true
      maximize_active_window
      navigate_to_url "$url"

      for _ in {1..20}; do
        if has_close_firefox_dialog; then
          log "Detected 'Close Firefox' dialog shortly after launch; retrying"
          wid=""
          break
        fi
        sleep 0.25
      done

      if [ -n "$wid" ]; then
        return 0
      fi
    fi

    log "Browser did not start cleanly on attempt ${attempt}."
    tail -n 80 "$FIREFOX_LOG_FILE" 2>/dev/null || true
    sleep 2
  done

  log "ERROR: Failed to start browser cleanly after ${attempts} attempts"
  return 1
}

api_login() {
  local username="$1"
  local password="$2"

  local payload
  payload=$(jq -nc --arg user "$username" --arg pass "$password" '{user: $user, password: $pass}')

  local response
  response=$(curl -sS -X POST \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

  if [ -z "$response" ]; then
    return 1
  fi

  local token
  token=$(echo "$response" | jq -r '.data.authToken // empty' 2>/dev/null || true)
  [ -n "$token" ]
}

display_dimensions() {
  local dims
  dims=$(DISPLAY=:1 xdpyinfo 2>/dev/null | awk '/dimensions:/ {print $2; exit}')
  if [ -z "$dims" ]; then
    echo "1920 1080"
    return 0
  fi

  local width="${dims%x*}"
  local height="${dims#*x}"
  echo "$width $height"
}

export -f log
export -f wait_for_http
export -f wait_for_window
export -f has_close_firefox_dialog
export -f dismiss_close_firefox_dialog
export -f get_firefox_window_id
export -f focus_window
export -f maximize_active_window
export -f focus_firefox
export -f take_screenshot
export -f stop_firefox
export -f clear_firefox_profile_locks
export -f navigate_to_url
export -f wait_for_firefox_main_window
export -f restart_firefox
export -f api_login
export -f display_dimensions
