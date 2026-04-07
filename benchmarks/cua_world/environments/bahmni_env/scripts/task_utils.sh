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

# Use Firefox browser (consistent with post_start warmup and rancher_env pattern).
# Firefox with certutil cert import reliably handles self-signed certs.
BROWSER_CMD="firefox"

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
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then
      return 0
    fi
    sleep 0.5
    elapsed=$((elapsed + 1))
  done

  return 1
}

get_browser_window_id() {
  # Get browser window ID (exclude taskbar @!0,0)
  # Look for browser windows by title (Firefox, Epiphany, Bahmni, etc.)
  DISPLAY=:1 wmctrl -l 2>/dev/null \
    | awk '{title=""; for(i=4;i<=NF;i++) title=title " " $i; title=substr(title,2); print $1, title}' \
    | grep -iv '@!0,0' \
    | grep -i 'firefox\|mozilla\|epiphany\|bahmni\|security\|violation\|openmrs\|localhost\|home\|login' \
    | awk '{print $1; exit}'
}

get_browser_window_id_any() {
  # Get any non-taskbar window ID (fallback)
  DISPLAY=:1 wmctrl -l 2>/dev/null \
    | awk '{title=""; for(i=4;i<=NF;i++) title=title " " $i; title=substr(title,2); print $1, title}' \
    | grep -iv '@!0,0' \
    | grep -v '^$' \
    | awk '{print $1; exit}'
}

focus_window() {
  local window_id="$1"
  DISPLAY=:1 wmctrl -ia "$window_id" 2>/dev/null \
    || DISPLAY=:1 wmctrl -a "$window_id" 2>/dev/null \
    || return 1
  sleep 0.3
  return 0
}

maximize_active_window() {
  DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
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
    DISPLAY=:1 xwd -id "$wid" -out /tmp/_ss.xwd 2>/dev/null \
      && convert /tmp/_ss.xwd "$output_file" 2>/dev/null \
      && rm -f /tmp/_ss.xwd 2>/dev/null \
      && return 0
  fi
  # Fallback to root window
  DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
}

stop_browser() {
  pkill -TERM -f 'firefox' 2>/dev/null || true
  pkill -TERM -f 'epiphany' 2>/dev/null || true

  local i=0
  while [ "$i" -lt 10 ]; do
    if pgrep -f 'firefox\|epiphany' >/dev/null 2>&1; then
      sleep 0.5
    else
      break
    fi
    i=$((i + 1))
  done

  pkill -KILL -f 'firefox' 2>/dev/null || true
  pkill -KILL -f 'epiphany' 2>/dev/null || true
  sleep 1

  # Clean Firefox lock files
  find /home/ga/.mozilla/firefox/ -name ".parentlock" -delete 2>/dev/null || true
  find /home/ga/.mozilla/firefox/ -name "lock" -delete 2>/dev/null || true
  find /home/ga/snap/firefox/ -name ".parentlock" -delete 2>/dev/null || true
  find /home/ga/snap/firefox/ -name "lock" -delete 2>/dev/null || true
}

dismiss_ssl_warning() {
  # Dismiss Firefox SSL cert warning using mouse clicks.
  # Coordinates measured from actual 1920x1080 maximized Firefox screenshot:
  #   "Advanced..." button: center at (1000, 535)
  #   "Accept the Risk and Continue": center at approximately (570, 670)

  local wid
  wid=$(get_browser_window_id)
  if [ -z "$wid" ]; then
    wid=$(get_browser_window_id_any)
  fi
  if [ -z "$wid" ]; then
    return 0  # No browser window
  fi

  # Focus and maximize the browser
  focus_window "$wid" || true
  maximize_active_window
  sleep 1

  # Get the window title
  local win_title
  win_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' \
    | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' | head -1 | xargs)

  # If Firefox View is showing (from a previous failed dismiss), click the SSL warning tab
  if echo "$win_title" | grep -qi "Firefox View"; then
    log "Firefox View detected, switching to SSL warning tab..."
    # Click on the first tab (the SSL warning tab) at approximately (160, 65)
    DISPLAY=:1 xdotool mousemove 160 65 click 1 2>/dev/null || true
    sleep 2
    win_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' \
      | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' | head -1 | xargs)
  fi

  # Check if the SSL warning is showing
  if ! echo "$win_title" | grep -qi "security\|warning\|risk\|error"; then
    return 0  # No SSL warning
  fi

  log "SSL warning detected: $win_title"
  log "Dismissing with mouse clicks..."

  # Coordinates from visual_grounding at 1280x720, scaled ×1.5 to 1920x1080:
  #   "Advanced..." button: VG (879, 470) → actual (1319, 705)

  # Step 1: Click "Advanced..." button at (1319, 705)
  DISPLAY=:1 xdotool mousemove 1319 705 click 1 2>/dev/null || true
  sleep 4

  # Step 2: Click "Accept the Risk and Continue" — estimated ~80-100px below Advanced
  DISPLAY=:1 xdotool mousemove 1319 800 click 1 2>/dev/null || true
  sleep 3

  # Verify - if still showing, try alternate positions
  win_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' \
    | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' | head -1 | xargs)
  if echo "$win_title" | grep -qi "security\|warning\|risk\|error"; then
    log "First accept click didn't work, trying alternates..."
    DISPLAY=:1 xdotool mousemove 1200 790 click 1 2>/dev/null || true
    sleep 2
    DISPLAY=:1 xdotool mousemove 1100 810 click 1 2>/dev/null || true
    sleep 2
  fi

  log "WARNING: SSL warning may not have been fully dismissed"
  return 1
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

  DISPLAY=:1 xdotool key --clearmodifiers ctrl+l 2>/dev/null || true
  sleep 0.5
  DISPLAY=:1 xdotool type --delay 20 --clearmodifiers "$url" 2>/dev/null || true
  sleep 0.2
  DISPLAY=:1 xdotool key --clearmodifiers Return 2>/dev/null || true
}

start_browser() {
  # Launch browser at the given URL.
  # Try Firefox first (proven reliable across all envs), fall back to Epiphany.
  local url="$1"
  local attempts="${2:-3}"

  # Wait for Bahmni/OpenMRS web service to be ready before launching browser
  wait_for_bahmni 120 || log "WARNING: Bahmni may not be ready, attempting browser launch anyway"

  for attempt in $(seq 1 "$attempts"); do
    log "Starting browser (attempt ${attempt}/${attempts}): $url"

    # Kill any existing browser processes
    stop_browser
    pkill -9 -f firefox 2>/dev/null || true
    sleep 3

    # Clean Firefox lock files
    find /home/ga/.mozilla/firefox/ -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga/.mozilla/firefox/ -name "lock" -delete 2>/dev/null || true
    find /home/ga/snap/firefox/ -name ".parentlock" -delete 2>/dev/null || true
    find /home/ga/snap/firefox/ -name "lock" -delete 2>/dev/null || true

    rm -f "$BROWSER_LOG_FILE" 2>/dev/null || true

    # Use Firefox (matching proven rancher_env pattern)
    log "Launching Firefox as ga user"
    su - ga -c "DISPLAY=:1 setsid firefox '${url}' > '${BROWSER_LOG_FILE}' 2>&1 &"

    # Wait for window to appear (up to 60s — snap Firefox is slow)
    sleep 10
    local elapsed=0
    local wid=""
    while [ "$elapsed" -lt 50 ]; do
      wid=$(get_browser_window_id_any)
      if [ -n "$wid" ]; then
        break
      fi
      sleep 1
      elapsed=$((elapsed + 1))
    done

    if [ -z "$wid" ]; then
      log "Firefox window did not appear on attempt ${attempt}"
      log "Browser log:"
      tail -10 "$BROWSER_LOG_FILE" 2>/dev/null || true
      log "All windows:"
      DISPLAY=:1 wmctrl -l 2>/dev/null || true
      log "Firefox processes:"
      ps aux | grep -i firefox 2>/dev/null | grep -v grep || true
      sleep 2
      continue
    fi

    # Focus and maximize
    focus_window "$wid" || true
    maximize_active_window
    sleep 2

    # Check for and dismiss SSL warning if present
    dismiss_ssl_warning
    sleep 2

    # After SSL dismissal, check if we ended up on Firefox View or wrong page
    local cur_title
    cur_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' \
      | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' | head -1 | xargs)
    if echo "$cur_title" | grep -qi "Firefox View\|New Tab\|about:"; then
      log "On Firefox View/New Tab after SSL dismiss, navigating to $url..."
      navigate_to_url "$url"
      sleep 8
      # May need to dismiss SSL warning again for the new navigation
      dismiss_ssl_warning
      sleep 2
    fi

    # Wait for page to load (up to 30s)
    local page_wait=0
    local ssl_dismiss_attempts=0
    while [ "$page_wait" -lt 30 ]; do
      local title
      title=$(DISPLAY=:1 wmctrl -l 2>/dev/null \
        | awk '{title=""; for(i=4;i<=NF;i++) title=title " " $i; print title}' \
        | grep -iv '@!0,0' | head -1)
      # Accept any browser window showing Bahmni/OpenMRS content
      if echo "$title" | grep -qi "bahmni\|home\|login\|openmrs\|admin"; then
        break
      fi
      # If SSL warning still showing, try dismiss (max 2 additional attempts)
      if echo "$title" | grep -qi "security\|warning\|risk"; then
        if [ "$ssl_dismiss_attempts" -lt 2 ]; then
          dismiss_ssl_warning
          ssl_dismiss_attempts=$((ssl_dismiss_attempts + 1))
          sleep 3
        fi
      fi
      # Firefox window exists with non-warning title — accept it
      if echo "$title" | grep -qi "mozilla\|firefox\|localhost"; then
        if ! echo "$title" | grep -qi "security\|warning\|risk\|error\|Firefox View\|New Tab"; then
          break
        fi
      fi
      sleep 1
      page_wait=$((page_wait + 1))
    done

    local win_title
    win_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null \
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
