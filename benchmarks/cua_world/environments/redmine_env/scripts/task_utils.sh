#!/bin/bash
# Shared utilities for Redmine task setup scripts

set -euo pipefail

REDMINE_BASE_URL="http://localhost:3000"
REDMINE_LOGIN_URL="$REDMINE_BASE_URL/login"
SEED_RESULT_FILE="/tmp/redmine_seed_result.json"
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
FIREFOX_LOG_FILE="/tmp/firefox_task.log"
# Snap Firefox requires an explicit DBUS session socket path
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"
export DBUS_SESSION_BUS_ADDRESS

log() {
  echo "[redmine_task] $*"
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
    sleep 0.5
    elapsed=$((elapsed + 1))
  done

  return 1
}

has_close_firefox_dialog() {
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "Close Firefox"
}

dismiss_close_firefox_dialog() {
  # Dismiss any "Close Firefox" dialog by pressing Enter (OK button)
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
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -ia "$window_id" 2>/dev/null || DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -a "$window_id" 2>/dev/null || return 1
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

take_screenshot() {
  local output_file="${1:-/tmp/screenshot.png}"
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$output_file" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot "$output_file" 2>/dev/null || true
}

stop_firefox() {
  pkill -TERM -f firefox 2>/dev/null || true
  for _ in {1..40}; do
    if pgrep -f firefox >/dev/null 2>&1; then
      sleep 0.5
    else
      break
    fi
  done
  if pgrep -f firefox >/dev/null 2>&1; then
    pkill -KILL -f firefox 2>/dev/null || true
    sleep 1
  fi
}

clear_firefox_profile_locks() {
  # Clear locks and session restore files from regular and snap Firefox profile paths.
  # Removing sessionstore files prevents Firefox from showing the about:sessionrestore
  # tab on next launch (which happens when Firefox was previously force-killed).
  for pdir in \
    "$FIREFOX_PROFILE_DIR" \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile"; do
    rm -f \
      "$pdir/lock" \
      "$pdir/.parentlock" \
      "$pdir/parent.lock" \
      "$pdir/singletonLock" \
      "$pdir/singletonCookie" \
      "$pdir/singletonSocket" \
      "$pdir/sessionstore.jsonlz4" \
      2>/dev/null || true
    rm -rf "$pdir/sessionstore-backups" 2>/dev/null || true
  done
}

navigate_to_url() {
  local url="$1"
  if ! has_command xdotool; then
    return 0
  fi
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers ctrl+l 2>/dev/null || true
  sleep 0.2
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --delay 15 --clearmodifiers "$url" 2>/dev/null || true
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers Return 2>/dev/null || true
}

wait_for_firefox_main_window() {
  local timeout_sec="${1:-30}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout_sec" ]; do
    if has_close_firefox_dialog; then
      log "Detected 'Close Firefox' dialog; dismissing..."
      dismiss_close_firefox_dialog
      sleep 1
    else
      local wid
      wid=$(get_firefox_window_id)
      if [ -n "$wid" ]; then
        echo "$wid"
        return 0
      fi
    fi

    sleep 0.5
    elapsed=$((elapsed + 1))
  done

  return 1
}

restart_firefox() {
  local url="$1"
  local attempts="${2:-3}"

  # Wait for Redmine web service to be ready before launching Firefox
  wait_for_http "$REDMINE_LOGIN_URL" 120 || log "WARNING: Redmine may not be ready, attempting Firefox launch anyway"

  # Dismiss any pre-existing "Close Firefox" dialog (e.g. from GNOME session restore)
  dismiss_close_firefox_dialog

  for attempt in $(seq 1 "$attempts"); do
    log "Starting Firefox (attempt ${attempt}/${attempts}): $url"

    stop_firefox
    dismiss_close_firefox_dialog
    clear_firefox_profile_locks
    rm -f "$FIREFOX_LOG_FILE" 2>/dev/null || true

    sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus firefox '$url' > '$FIREFOX_LOG_FILE' 2>&1 &"

    local wid=""
    if wid=$(wait_for_firefox_main_window 30); then
      focus_window "$wid" || true
      maximize_active_window
      navigate_to_url "$url"
      local title
      title=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool getactivewindow getwindowname 2>/dev/null || true)
      [ -n "${title:-}" ] && log "Firefox window title: $title"
      return 0
    fi

    log "Firefox did not start cleanly on attempt ${attempt}."
    tail -n 40 "$FIREFOX_LOG_FILE" 2>/dev/null || true
    sleep 2
  done

  log "ERROR: Failed to start Firefox cleanly after ${attempts} attempts."
  return 1
}

# Get issue ID by subject substring (from seed result)
redmine_issue_id_by_subject() {
  local subject_fragment="$1"
  if [ ! -f "$SEED_RESULT_FILE" ]; then
    echo ""
    return 0
  fi
  jq -r --arg s "$subject_fragment" \
    '.issues[] | select(.subject | ascii_downcase | contains($s | ascii_downcase)) | .id' \
    "$SEED_RESULT_FILE" 2>/dev/null | head -n 1
}

# Get project id by identifier
redmine_project_id() {
  local identifier="$1"
  if [ ! -f "$SEED_RESULT_FILE" ]; then
    echo ""
    return 0
  fi
  jq -r --arg id "$identifier" \
    '.projects[] | select(.identifier==$id) | .id' \
    "$SEED_RESULT_FILE" 2>/dev/null | head -n 1
}

# Get admin API key
redmine_admin_api_key() {
  if [ -f "$SEED_RESULT_FILE" ]; then
    jq -r '.admin_api_key' "$SEED_RESULT_FILE" 2>/dev/null || true
  fi
}

# Build URL for a Redmine issue
redmine_issue_url() {
  local issue_id="$1"
  echo "$REDMINE_BASE_URL/issues/$issue_id"
}

# Log in to Redmine using xdotool to fill the login form, then navigate to target URL.
# Stops any running Firefox, launches it at the login page, fills credentials via
# xdotool keyboard/mouse automation (works from root hook context), then navigates
# to the target URL.
# Args: $1=target URL to navigate to after login
ensure_redmine_logged_in() {
  local target_url="${1:-$REDMINE_BASE_URL/my/page}"

  # Wait for Redmine web service to be ready before launching Firefox
  wait_for_http "$REDMINE_LOGIN_URL" 120 || log "WARNING: Redmine may not be ready, attempting login anyway"

  log "Logging in to Redmine via xdotool..."

  # Step 1: Stop any running Firefox and clear profile locks
  stop_firefox
  clear_firefox_profile_locks
  rm -f "$FIREFOX_LOG_FILE" 2>/dev/null || true

  # Step 2: Launch Firefox at the login page as ga user
  # Using su - ga -c because it loads the ga user environment including snap paths
  su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus firefox '$REDMINE_LOGIN_URL' > '$FIREFOX_LOG_FILE' 2>&1 &"

  # Step 3: Wait for Firefox main window
  local wid=""
  if ! wid=$(wait_for_firefox_main_window 30); then
    log "ERROR: Firefox did not start (attempt 2)"
    # Retry with sudo -u ga
    sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus firefox '$REDMINE_LOGIN_URL' > '$FIREFOX_LOG_FILE' 2>&1 &"
    wid=$(wait_for_firefox_main_window 30) || true
  fi

  if [ -z "$wid" ]; then
    log "ERROR: Firefox failed to start for login"
    return 1
  fi

  # Step 4: Focus and maximize Firefox
  focus_window "$wid" || true
  maximize_active_window
  sleep 4  # Wait for login page to fully render

  # Step 5: Fill login form via xdotool
  # Coordinates (1920x1080): username=(996,398), password=(996,467), Login btn=(996,510)
  # Focus the Firefox window first
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool windowfocus --sync "$wid" 2>/dev/null || true
  sleep 0.5

  # Click username field
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove --sync 996 398 2>/dev/null || true
  sleep 0.3
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool click 1 2>/dev/null || true
  sleep 0.5
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers ctrl+a 2>/dev/null || true
  sleep 0.2
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --delay 50 --clearmodifiers "admin" 2>/dev/null || true
  sleep 0.5

  # Click password field
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove --sync 996 467 2>/dev/null || true
  sleep 0.3
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool click 1 2>/dev/null || true
  sleep 0.5
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --delay 50 --clearmodifiers "Admin1234!" 2>/dev/null || true
  sleep 0.5

  # Press Return to submit (more reliable than clicking Login button)
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers Return 2>/dev/null || true
  sleep 6

  log "Login submitted, navigating to: $target_url"

  # Step 6: Navigate to target URL via address bar
  wid=$(get_firefox_window_id)
  if [ -n "$wid" ]; then
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool windowfocus --sync "$wid" 2>/dev/null || true
    sleep 0.3
  fi
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers ctrl+l 2>/dev/null || true
  sleep 0.3
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers ctrl+a 2>/dev/null || true
  sleep 0.2
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --delay 20 --clearmodifiers "$target_url" 2>/dev/null || true
  sleep 0.3
  DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key --clearmodifiers Return 2>/dev/null || true
  sleep 5

  log "Navigated to $target_url"
  return 0
}

export -f wait_for_http
export -f wait_for_window
export -f has_close_firefox_dialog
export -f get_firefox_window_id
export -f focus_window
export -f maximize_active_window
export -f focus_firefox
export -f take_screenshot
export -f log
export -f stop_firefox
export -f dismiss_close_firefox_dialog
export -f clear_firefox_profile_locks
export -f navigate_to_url
export -f wait_for_firefox_main_window
export -f restart_firefox
export -f redmine_issue_id_by_subject
export -f redmine_project_id
export -f redmine_admin_api_key
export -f redmine_issue_url
export -f ensure_redmine_logged_in
