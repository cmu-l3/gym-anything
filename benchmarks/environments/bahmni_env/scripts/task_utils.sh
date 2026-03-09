#!/bin/bash
# Shared task setup utilities for Bahmni tasks.
# Note: No set -euo pipefail here - this file is sourced by other scripts
# and pipefail would cause premature exit when browser commands return non-zero.

# Bahmni proxy redirects HTTP -> HTTPS. Use HTTPS with -k for self-signed cert.
BAHMNI_BASE_URL="https://localhost"
BAHMNI_LOGIN_URL="${BAHMNI_BASE_URL}/bahmni/home"
OPENMRS_BASE_URL="${BAHMNI_BASE_URL}/openmrs"
OPENMRS_API_URL="${OPENMRS_BASE_URL}/ws/rest/v1"
BROWSER_LOG_FILE="/tmp/browser_bahmni_task.log"
SEED_MANIFEST_FILE="/tmp/bahmni_seed_manifest.json"
BAHMNI_ADMIN_USERNAME="superman"
BAHMNI_ADMIN_PASSWORD="Admin123"

# Use Epiphany browser (consistent with post_start warmup).
# Epiphany renders Bahmni's Angular JS app correctly.
# XAUTHORITY must be set to the GDM keyring path (not ~/.Xauthority which is empty).
XAUTHORITY_PATH="/run/user/1000/gdm/Xauthority"
BROWSER_CMD="epiphany-browser"

log() {
  echo "[bahmni_task] $*"
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
    code=$(curl -sk -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
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

wait_for_bahmni() {
  local timeout_sec="${1:-900}"
  # Use the OpenMRS session API as the readiness check for Bahmni
  wait_for_http "${OPENMRS_API_URL}/session" "$timeout_sec"
}

wait_for_window() {
  local window_pattern="$1"
  local timeout="${2:-30}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout" ]; do
    if DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then
      return 0
    fi
    sleep 0.5
    elapsed=$((elapsed + 1))
  done

  return 1
}

get_browser_window_id() {
  # Get Epiphany browser window ID (exclude taskbar @!0,0)
  # Look for Epiphany windows by title (Bahmni, Security, login, home, localhost)
  DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" wmctrl -l 2>/dev/null \
    | awk '{title=""; for(i=4;i<=NF;i++) title=title " " $i; title=substr(title,2); print $1, title}' \
    | grep -iv '@!0,0' \
    | grep -i 'epiphany\|bahmni\|security\|violation\|openmrs\|localhost\|home\|login' \
    | awk '{print $1; exit}'
}

get_browser_window_id_any() {
  # Get any non-taskbar window ID (fallback)
  DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" wmctrl -l 2>/dev/null \
    | awk '{title=""; for(i=4;i<=NF;i++) title=title " " $i; title=substr(title,2); print $1, title}' \
    | grep -iv '@!0,0' \
    | grep -v '^$' \
    | awk '{print $1; exit}'
}

focus_window() {
  local window_id="$1"
  DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" wmctrl -ia "$window_id" 2>/dev/null \
    || DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" wmctrl -a "$window_id" 2>/dev/null \
    || return 1
  sleep 0.3
  return 0
}

maximize_active_window() {
  DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
}

focus_browser() {
  local wid
  wid=$(get_browser_window_id)
  if [ -z "$wid" ]; then
    wid=$(get_browser_window_id_any)
  fi
  if [ -n "$wid" ]; then
    focus_window "$wid" || true
    maximize_active_window
    return 0
  fi
  return 1
}

take_screenshot() {
  # Use xwd to capture the browser window directly (import/scrot give black output
  # in this GNOME compositor environment).
  local output_file="${1:-/tmp/screenshot.png}"
  local wid
  wid=$(get_browser_window_id)
  if [ -z "$wid" ]; then
    wid=$(get_browser_window_id_any)
  fi
  if [ -n "$wid" ]; then
    DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" xwd -id "$wid" -out /tmp/_ss.xwd 2>/dev/null \
      && convert /tmp/_ss.xwd "$output_file" 2>/dev/null \
      && rm -f /tmp/_ss.xwd 2>/dev/null \
      && return 0
  fi
  # Fallback to root window
  DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" import -window root "$output_file" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" scrot "$output_file" 2>/dev/null || true
}

stop_browser() {
  pkill -TERM -f 'epiphany' 2>/dev/null || true

  local i=0
  while [ "$i" -lt 20 ]; do
    if pgrep -f 'epiphany' >/dev/null 2>&1; then
      sleep 0.5
    else
      break
    fi
    i=$((i + 1))
  done

  if pgrep -f 'epiphany' >/dev/null 2>&1; then
    pkill -KILL -f 'epiphany' 2>/dev/null || true
    sleep 1
  fi
}

dismiss_ssl_warning() {
  # Epiphany shows "Security Violation" for Bahmni's self-signed cert.
  # This function detects and dismisses it by:
  # 1. Clicking "Technical information" to expand
  # 2. Clicking "Accept Risk and Proceed"
  #
  # Coordinates (for 1850x1053 window, measured via visual_grounding):
  #   Technical information: actual (707, 706) [VG 489,483 at 1280x720]
  #   Accept Risk and Proceed: actual (717, 770) [VG 496,527 at 1280x720]

  local wid
  wid=$(DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" wmctrl -l 2>/dev/null \
    | grep -i "Security Violation" \
    | awk '{print $1; exit}')

  if [ -z "$wid" ]; then
    return 0  # No SSL warning present
  fi

  log "SSL warning detected, dismissing..."

  # Focus and maximize the warning window
  DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" wmctrl -ia "$wid" 2>/dev/null || true
  sleep 0.3
  DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
  sleep 0.5

  # Click "Technical information" to expand (actual: 707, 706)
  DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" xdotool mousemove --window "$wid" 707 706 click 1 2>/dev/null || true
  sleep 1.5

  # Click "Accept Risk and Proceed" (actual: 717, 770)
  DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" xdotool mousemove --window "$wid" 717 770 click 1 2>/dev/null || true
  sleep 5

  # Verify SSL was dismissed
  if DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" wmctrl -l 2>/dev/null | grep -qi "Security Violation"; then
    log "WARNING: SSL warning still visible after dismissal attempt"
    return 1
  fi

  log "SSL warning dismissed"
  return 0
}

navigate_to_url() {
  local url="$1"

  if ! has_command xdotool; then
    return 0
  fi

  # Focus browser first, then use Ctrl+L to open address bar
  local wid
  wid=$(get_browser_window_id)
  if [ -z "$wid" ]; then
    wid=$(get_browser_window_id_any)
  fi
  if [ -n "$wid" ]; then
    focus_window "$wid" || true
    sleep 0.3
  fi

  DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" xdotool key --clearmodifiers ctrl+l 2>/dev/null || true
  sleep 0.5
  DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" xdotool type --delay 20 --clearmodifiers "$url" 2>/dev/null || true
  sleep 0.2
  DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" xdotool key --clearmodifiers Return 2>/dev/null || true
}

start_browser() {
  # Launch Epiphany at the given URL.
  # Epiphany does NOT persist SSL cert exceptions across restarts, so we
  # detect and dismiss the SSL warning every time.
  local url="$1"
  local attempts="${2:-4}"

  for attempt in $(seq 1 "$attempts"); do
    log "Starting Epiphany browser (attempt ${attempt}/${attempts}): $url"

    stop_browser
    sleep 1
    rm -f "$BROWSER_LOG_FILE" 2>/dev/null || true

    # Launch Epiphany in the background.
    # GDK_BACKEND=x11 is required for Epiphany to display on X11 from SSH.
    bash -c "DISPLAY=:1 XAUTHORITY=${XAUTHORITY_PATH} GDK_BACKEND=x11 epiphany-browser '${url}' > '${BROWSER_LOG_FILE}' 2>&1 &"

    # Wait for window to appear (up to 30s)
    local elapsed=0
    local wid=""
    while [ "$elapsed" -lt 30 ]; do
      wid=$(get_browser_window_id_any)
      if [ -n "$wid" ]; then
        break
      fi
      sleep 1
      elapsed=$((elapsed + 1))
    done

    if [ -z "$wid" ]; then
      log "Epiphany window did not appear on attempt ${attempt}"
      tail -5 "$BROWSER_LOG_FILE" 2>/dev/null || true
      sleep 2
      continue
    fi

    # Focus and maximize
    focus_window "$wid" || true
    maximize_active_window
    sleep 0.5

    # Dismiss SSL warning if present
    dismiss_ssl_warning

    # Wait for Bahmni page to load (up to 20s)
    local page_wait=0
    while [ "$page_wait" -lt 20 ]; do
      local title
      title=$(DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" wmctrl -l 2>/dev/null \
        | awk '{title=""; for(i=4;i<=NF;i++) title=title " " $i; print title}' \
        | grep -iv '@!0,0' | head -1)
      if echo "$title" | grep -qi "bahmni\|home\|login\|openmrs"; then
        break
      fi
      sleep 1
      page_wait=$((page_wait + 1))
    done

    local win_title
    win_title=$(DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" wmctrl -l 2>/dev/null \
      | grep -v '@!0,0' \
      | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' \
      | head -1 | xargs)
    log "Browser ready (window: ${win_title})"
    return 0
  done

  log "ERROR: Failed to start browser after ${attempts} attempts"
  return 1
}

# Aliases for compatibility with task scripts
restart_firefox() {
  start_browser "$@"
}

restart_browser() {
  start_browser "$@"
}

focus_firefox() {
  focus_browser "$@"
}

openmrs_api_get() {
  local endpoint="$1"
  # Use -k to skip SSL cert verification (Bahmni uses self-signed cert)
  curl -skS \
    -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    -H "Content-Type: application/json" \
    "${OPENMRS_API_URL}${endpoint}" 2>/dev/null || true
}

openmrs_api_post() {
  local endpoint="$1"
  local payload="$2"
  # Use -k to skip SSL cert verification (Bahmni uses self-signed cert)
  curl -skS -X POST \
    -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${OPENMRS_API_URL}${endpoint}" 2>/dev/null || true
}

get_patient_uuid_by_identifier() {
  local identifier="$1"
  local response
  response=$(openmrs_api_get "/patient?identifier=${identifier}&v=default")
  echo "$response" | jq -r '.results[0].uuid // empty' 2>/dev/null || true
}

display_dimensions() {
  local dims
  dims=$(DISPLAY=:1 XAUTHORITY="${XAUTHORITY_PATH}" xdpyinfo 2>/dev/null | awk '/dimensions:/ {print $2; exit}')
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
export -f wait_for_bahmni
export -f wait_for_window
export -f get_browser_window_id
export -f get_browser_window_id_any
export -f focus_window
export -f maximize_active_window
export -f focus_browser
export -f focus_firefox
export -f take_screenshot
export -f stop_browser
export -f dismiss_ssl_warning
export -f navigate_to_url
export -f start_browser
export -f restart_firefox
export -f restart_browser
export -f openmrs_api_get
export -f openmrs_api_post
export -f get_patient_uuid_by_identifier
export -f display_dimensions
