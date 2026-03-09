#!/bin/bash
# Shared utilities for Socioboard environment tasks
# Source this file at the start of each setup_task.sh:
#   source /workspace/scripts/task_utils.sh

SOCR_URL="http://localhost"
DB_NAME="socioboard"
DB_USER="socioboard"
DB_PASS="SocioPass2024!"
ADMIN_EMAIL="admin@socioboard.local"
ADMIN_PASS="Admin2024!"

# ============================================================
# Logging
# ============================================================
log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

# ============================================================
# Take screenshot
# ============================================================
take_screenshot() {
  local path="${1:-/tmp/screenshot.png}"
  DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# ============================================================
# Wait for HTTP endpoint
# ============================================================
wait_for_http() {
  local url="$1"
  local timeout_sec="${2:-120}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout_sec" ]; do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || true)
    if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "301" ]; then
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  return 1
}

# ============================================================
# Database query helper
# ============================================================
socioboard_query() {
  local query="$1"
  mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "$query" 2>/dev/null || \
    mysql -u root "$DB_NAME" -N -e "$query" 2>/dev/null || true
}

# ============================================================
# Focus Firefox window
# ============================================================
focus_firefox() {
  DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "Firefox" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -a "Firefox" 2>/dev/null || true
  sleep 0.5
}

# ============================================================
# Navigate Firefox to URL
# ============================================================
navigate_to() {
  local url="$1"
  log "Navigating Firefox to: $url"
  focus_firefox
  sleep 0.5
  DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key ctrl+l
  sleep 0.3
  DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool type --clearmodifiers "$url"
  sleep 0.3
  DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return
  sleep 3
}

# ============================================================
# Ensure Firefox is running and pointed to Socioboard
# ============================================================
ensure_firefox_running() {
  local url="${1:-$SOCR_URL/}"
  log "Checking Firefox..."

  # Check if Firefox is running
  if ! pgrep -f "firefox" > /dev/null 2>&1; then
    log "Firefox not running, launching..."
    pkill -9 -f firefox 2>/dev/null || true
    sleep 1

    # Remove lock files
    rm -f /home/ga/snap/firefox/common/.mozilla/firefox/socioboard.profile/.parentlock 2>/dev/null || true
    rm -f /home/ga/snap/firefox/common/.mozilla/firefox/socioboard.profile/lock 2>/dev/null || true
    rm -f /home/ga/.mozilla/firefox/socioboard.profile/.parentlock 2>/dev/null || true

    su - ga -c "
      DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
      XDG_RUNTIME_DIR=/run/user/1000 \
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
      setsid firefox --new-instance \
        -profile /home/ga/snap/firefox/common/.mozilla/firefox/socioboard.profile \
        '$url' > /tmp/firefox_task.log 2>&1 &
    " || \
    su - ga -c "
      DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority \
      setsid firefox -profile /home/ga/.mozilla/firefox/socioboard.profile \
        '$url' > /tmp/firefox_task.log 2>&1 &
    " || true

    sleep 5

    # Wait for window
    for i in $(seq 1 20); do
      if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        break
      fi
      sleep 1
    done
  fi

  # Maximize
  DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: \
    -b add,maximized_vert,maximized_horz 2>/dev/null || true
  sleep 1
}

# ============================================================
# Navigate to URL in existing Firefox (or launch)
# ============================================================
open_socioboard_page() {
  local url="$1"
  ensure_firefox_running "$url"
  sleep 1
  navigate_to "$url"
  sleep 2
}

log "task_utils.sh loaded (Socioboard URL: $SOCR_URL)"
