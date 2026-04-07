#!/bin/bash
# Shared utilities for Casebox task setup scripts

CASEBOX_BASE_URL="http://localhost/c/default"
CASEBOX_LOGIN_URL="$CASEBOX_BASE_URL/login"
SEED_RESULT_FILE="/tmp/casebox_seed_result.json"
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
FIREFOX_LOG_FILE="/tmp/firefox_task.log"
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"
export DBUS_SESSION_BUS_ADDRESS

log() {
  echo "[casebox_task] $*"
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
    if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "303" ]; then
      log "HTTP ready after ${elapsed}s (HTTP $code)"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    log "  waiting... ${elapsed}s (HTTP $code)"
  done
  log "ERROR: Timeout waiting for HTTP readiness: $url"
  return 1
}

wait_for_window() {
  local window_pattern="$1"
  local timeout=${2:-30}
  local elapsed=0

  while [ $elapsed -lt $timeout ]; do
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  return 1
}

has_close_firefox_dialog() {
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "Close Firefox"
}

dismiss_close_firefox_dialog() {
  local wid
  wid=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i "Close Firefox" | awk '{print $1; exit}')
  if [ -n "$wid" ]; then
    log "Dismissing 'Close Firefox' dialog (window $wid)..."
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -ia "$wid" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return 2>/dev/null || true
    sleep 1
  fi
}

get_firefox_window_id() {
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | grep -vi 'close firefox' | awk '{print $1; exit}'
}

focus_window() {
  local window_id="$1"
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -ia "$window_id" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -a "$window_id" 2>/dev/null || return 1
  sleep 0.3
  return 0
}

maximize_active_window() {
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
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

kill_firefox() {
  log "Killing existing Firefox instances..."
  pkill -f firefox 2>/dev/null || true
  sleep 2
  pkill -9 -f firefox 2>/dev/null || true
  sleep 1
}

launch_firefox() {
  local url="$1"
  log "Launching Firefox at: $url"

  # Kill existing Firefox
  kill_firefox

  # Dismiss any leftover close dialogs
  dismiss_close_firefox_dialog

  # Launch Firefox
  su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus setsid firefox '$url' > $FIREFOX_LOG_FILE 2>&1 &"

  # Wait for window
  local timeout=30
  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
      log "Firefox window detected after ${elapsed}s"
      sleep 2
      focus_firefox || true
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  log "WARNING: Firefox window not detected within ${timeout}s"
  return 1
}

navigate_firefox() {
  local url="$1"
  log "Navigating Firefox to: $url"

  local wid
  wid=$(get_firefox_window_id)
  if [ -z "$wid" ]; then
    log "No Firefox window found, launching fresh..."
    launch_firefox "$url"
    return $?
  fi

  focus_window "$wid" || true
  sleep 0.5

  # Navigate via Ctrl+L (address bar)
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key ctrl+l
  sleep 0.5
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --delay 20 "$url"
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return
  sleep 3

  return 0
}

ensure_casebox_logged_in() {
  local target_url="${1:-$CASEBOX_BASE_URL}"
  log "Ensuring Casebox is loaded at: $target_url"

  # First check if Firefox is running
  local wid
  wid=$(get_firefox_window_id)
  if [ -z "$wid" ]; then
    launch_firefox "$target_url"
  else
    navigate_firefox "$target_url"
  fi

  sleep 3
  focus_firefox || true

  return 0
}

take_screenshot() {
  local path="${1:-/tmp/screenshot.png}"
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$path" 2>/dev/null || true
  log "Screenshot saved: $path"
}

casebox_query() {
  local query="$1"
  docker exec casebox-db mysql -u casebox -pCaseboxPass123 casebox -N -e "$query" 2>/dev/null
}

casebox_tree_count() {
  casebox_query "SELECT COUNT(*) FROM tree WHERE dstatus=0"
}

casebox_folder_by_name() {
  local name="$1"
  casebox_query "SELECT id FROM tree WHERE name LIKE '%${name}%' AND dstatus=0 LIMIT 1"
}
