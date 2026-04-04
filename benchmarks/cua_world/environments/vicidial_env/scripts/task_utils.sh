#!/bin/bash
# Shared utilities for Vicidial tasks

VICIDIAL_ADMIN_URL="${VICIDIAL_ADMIN_URL:-http://localhost/vicidial/admin.php}"

vicidial_ensure_running() {
  /usr/local/bin/vicidial-ensure-running
}

take_screenshot() {
  local path="${1:-/tmp/screenshot.png}"
  DISPLAY=:1 import -window root "$path" 2>/dev/null || \
  DISPLAY=:1 scrot "$path" 2>/dev/null || true
}

wait_for_window() {
  local pattern="$1"
  local timeout="${2:-30}"
  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  return 1
}

focus_firefox() {
  DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || \
  DISPLAY=:1 wmctrl -a "Mozilla" 2>/dev/null || true
  sleep 1
}

maximize_active_window() {
  DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
}

navigate_to_url() {
  local url="$1"
  DISPLAY=:1 xdotool key ctrl+l
  sleep 0.3
  DISPLAY=:1 xdotool type --delay 20 "$url"
  sleep 0.2
  DISPLAY=:1 xdotool key Return
  sleep 3
}

