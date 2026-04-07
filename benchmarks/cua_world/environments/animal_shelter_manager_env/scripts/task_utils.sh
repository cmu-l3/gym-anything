#!/bin/bash
# Shared task setup utilities for Animal Shelter Manager tasks.

set -euo pipefail

ASM_BASE_URL="http://localhost:8080"
ASM_LOGIN_URL="${ASM_BASE_URL}/login"
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox/default-release"
FIREFOX_LOG_FILE="/tmp/firefox_asm_task.log"
ASM_TASK_USERNAME="user"
ASM_TASK_PASSWORD="letmein"

log() {
  echo "[asm_task] $*"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

wait_for_http() {
  local url="$1"
  local timeout_sec="${2:-120}"
  local elapsed=0

  log "Waiting for HTTP readiness: $url"

  while [ "$elapsed" -lt "$timeout_sec" ]; do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "401" ] || [ "$code" = "403" ]; then
      log "HTTP ready after ${elapsed}s (HTTP $code)"
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
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

get_firefox_window_id() {
  DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla\|shelter\|animal' | grep -vi 'close firefox' | awk '{print $1; exit}'
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
  pkill -TERM -f 'firefox' 2>/dev/null || true

  for _ in {1..40}; do
    if pgrep -f 'firefox' >/dev/null 2>&1; then
      sleep 0.5
    else
      break
    fi
  done

  if pgrep -f 'firefox' >/dev/null 2>&1; then
    pkill -KILL -f 'firefox' 2>/dev/null || true
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

navigate_to_url() {
  local url="$1"

  if ! has_command xdotool; then
    return 0
  fi

  DISPLAY=:1 xdotool key --clearmodifiers ctrl+l 2>/dev/null || true
  sleep 0.3
  DISPLAY=:1 xdotool type --delay 15 --clearmodifiers "$url" 2>/dev/null || true
  DISPLAY=:1 xdotool key --clearmodifiers Return 2>/dev/null || true
}

has_close_firefox_dialog() {
  DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Close Firefox"
}

dismiss_close_firefox_dialog() {
  local dialog_id
  dialog_id=$(DISPLAY=:1 wmctrl -l 2>/dev/null | awk 'tolower($0) ~ /close firefox/ {print $1; exit}')
  if [ -n "$dialog_id" ]; then
    focus_window "$dialog_id" || true
    DISPLAY=:1 xdotool key --clearmodifiers Return 2>/dev/null || true
    sleep 1
  fi
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

  wait_for_http "${ASM_BASE_URL}/login" 60 || log "WARNING: ASM3 may not be ready"

  for attempt in $(seq 1 "$attempts"); do
    log "Starting Firefox (attempt ${attempt}/${attempts}): $url"

    stop_firefox
    clear_firefox_profile_locks
    rm -f "$FIREFOX_LOG_FILE" 2>/dev/null || true

    # Use simple launch (snap Firefox needs more time, dbus-launch can fail)
    su - ga -c "DISPLAY=:1 firefox '$url' > '$FIREFOX_LOG_FILE' 2>&1 &"

    # Wait longer for snap-based Firefox (can take 30-40s on first launch)
    local wid=""
    if wid=$(wait_for_firefox_main_window 90); then
      focus_window "$wid" || true
      maximize_active_window
      sleep 2

      for _ in {1..20}; do
        if has_close_firefox_dialog; then
          log "Detected 'Close Firefox' dialog; retrying"
          wid=""
          break
        fi
        sleep 0.25
      done

      if [ -n "$wid" ]; then
        return 0
      fi
    fi

    log "Firefox did not start cleanly on attempt ${attempt}."
    sleep 2
  done

  log "ERROR: Failed to start Firefox after ${attempts} attempts"
  return 1
}

# Auto-login to ASM3 via xdotool after Firefox shows the login page.
# Waits for the login page to appear, types credentials, and submits.
# After login, waits for the dashboard to load and dismisses the welcome popup.
auto_login() {
  local target_url="${1:-${ASM_BASE_URL}/main}"
  local timeout=60
  local elapsed=0

  log "Waiting for login page to appear..."
  while [ "$elapsed" -lt "$timeout" ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "login"; then
      log "Login page detected after ${elapsed}s"
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  sleep 3
  focus_firefox || true
  maximize_active_window

  # Click in the page body, then Tab to the username field
  DISPLAY=:1 xdotool mousemove 480 400 click 1 2>/dev/null || true
  sleep 0.5
  DISPLAY=:1 xdotool key Tab 2>/dev/null || true
  sleep 0.3
  DISPLAY=:1 xdotool type --clearmodifiers --delay 20 "${ASM_TASK_USERNAME}" 2>/dev/null || true
  DISPLAY=:1 xdotool key Tab 2>/dev/null || true
  sleep 0.3
  DISPLAY=:1 xdotool type --clearmodifiers --delay 20 "${ASM_TASK_PASSWORD}" 2>/dev/null || true
  DISPLAY=:1 xdotool key Return 2>/dev/null || true

  log "Login submitted, waiting for dashboard..."
  sleep 8

  # Check if login succeeded by looking at window title
  if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Organisation\|Animal Shelter Manager -"; then
    log "Login successful"
  else
    log "WARNING: Login may not have succeeded"
  fi

  # Dismiss the welcome popup if present
  dismiss_welcome_popup

  # Dismiss any Firefox password save prompt
  DISPLAY=:1 xdotool key Escape 2>/dev/null || true
  sleep 1
}

# Dismiss the ASM3 welcome popup that appears on first login
dismiss_welcome_popup() {
  sleep 2
  # Press Escape to close the jQuery dialog
  DISPLAY=:1 xdotool key Escape 2>/dev/null || true
  sleep 1

  # Verify popup is gone - if still showing, try clicking outside
  if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Organisation"; then
    log "Welcome popup dismissed"
  fi
}

# Combined function: restart Firefox, auto-login, and navigate to target URL
restart_firefox_logged_in() {
  local target_url="${1:-${ASM_BASE_URL}/main}"

  restart_firefox "${ASM_BASE_URL}/main"
  auto_login
  sleep 2

  # Always navigate to the target URL after login to ensure correct page
  log "Navigating to target: $target_url"
  navigate_to_url "$target_url"
  sleep 5

  # Dismiss welcome popup again (it reappears on /main)
  dismiss_welcome_popup
  sleep 1

  focus_firefox || true
  maximize_active_window
}

# ASM3 database query helper
asm_query() {
  local query="$1"
  PGPASSWORD=asm psql -h localhost -U asm -d asm -t -c "$query" 2>/dev/null
}

# ASM3 database query returning full output (with headers)
asm_query_full() {
  local query="$1"
  PGPASSWORD=asm psql -h localhost -U asm -d asm -c "$query" 2>/dev/null
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
export -f get_firefox_window_id
export -f focus_window
export -f maximize_active_window
export -f focus_firefox
export -f take_screenshot
export -f stop_firefox
export -f clear_firefox_profile_locks
export -f navigate_to_url
export -f has_close_firefox_dialog
export -f dismiss_close_firefox_dialog
export -f wait_for_firefox_main_window
export -f restart_firefox
export -f auto_login
export -f dismiss_welcome_popup
export -f restart_firefox_logged_in
export -f asm_query
export -f asm_query_full
export -f display_dimensions
