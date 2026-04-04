#!/bin/bash
# Shared utilities for ManageEngine EventLog Analyzer task setup scripts
#
# NOTE: Do NOT use "set -euo pipefail" in setup_task.sh files that source this.
# See cross-cutting pattern #25: set -euo pipefail breaks source task_utils.sh

ELA_HOME="/opt/ManageEngine/EventLog"
ELA_URL="http://localhost:8095"
ADMIN_USER="admin"
ADMIN_PASS="admin"

# Firefox profile path (handles snap vs native Firefox)
get_firefox_profile_dir() {
    if [ -d "/home/ga/snap/firefox/common/.mozilla/firefox/ela.profile" ]; then
        echo "/home/ga/snap/firefox/common/.mozilla/firefox"
    else
        echo "/home/ga/.mozilla/firefox"
    fi
}

# Wait for EventLog Analyzer web UI to be accessible
# Uses 900s default to allow for background install + service start (takes up to ~15 min from boot).
# Args: $1 - timeout in seconds (default 900)
wait_for_eventlog_analyzer() {
    local timeout=${1:-900}
    local elapsed=0
    local ela_url="$ELA_URL/event/index.do"

    echo "Waiting for EventLog Analyzer at $ela_url (timeout: ${timeout}s)..." >&2

    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 5 "$ela_url" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
            echo "EventLog Analyzer ready after ${elapsed}s (HTTP $HTTP_CODE)" >&2
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        if [ $((elapsed % 60)) -eq 0 ]; then
            echo "  Still waiting... ${elapsed}s (HTTP $HTTP_CODE)" >&2
        fi
    done

    echo "WARNING: EventLog Analyzer not ready after ${timeout}s" >&2
    return 1
}

# Ensure Firefox is running and showing EventLog Analyzer
# Always kills any existing Firefox first, then starts fresh.
# This avoids "Firefox already running" dialogs from stale lock files or orphaned processes.
ensure_firefox_on_ela() {
    local ela_path="${1:-/event/index.do}"
    local full_url="${ELA_URL}${ela_path}"
    local profile_base
    profile_base=$(get_firefox_profile_dir)

    echo "Ensuring Firefox is open at $full_url..." >&2

    # Kill existing Firefox and wait until all processes are dead (handles snap Firefox chains)
    pkill -9 -f firefox 2>/dev/null || true
    local kill_wait=0
    while pgrep -f "firefox" > /dev/null 2>&1 && [ $kill_wait -lt 5 ]; do
        sleep 1
        kill_wait=$((kill_wait + 1))
    done
    # Second pass in case any snap child processes survived
    pkill -9 -f firefox 2>/dev/null || true
    sleep 1

    # Remove lock files (both native and snap profile paths)
    rm -f "$profile_base/ela.profile/.parentlock" \
          "$profile_base/ela.profile/lock" \
          "$profile_base/ela.profile/.mozilla-lock" 2>/dev/null || true
    rm -f /home/ga/.mozilla/firefox/ela.profile/.parentlock \
          /home/ga/.mozilla/firefox/ela.profile/lock 2>/dev/null || true

    echo "Starting Firefox..." >&2
    su - ga -c "
        export DISPLAY=:1
        export XAUTHORITY=/run/user/1000/gdm/Xauthority
        setsid firefox --new-instance \
            -profile '$profile_base/ela.profile' \
            '$full_url' \
            > /tmp/firefox_task.log 2>&1 &
    " 2>/dev/null || true
    sleep 8

    # Dismiss any "Firefox already running" dialog (press Enter to click OK)
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | \
            grep -qi "close firefox\|already running"; then
        echo "Dismissing 'Firefox already running' dialog..." >&2
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return
        sleep 3
    fi

    # Wait for Firefox window with EventLog Analyzer (60s - snap Firefox can be slow to start)
    wait_for_window "firefox\|mozilla\|EventLog\|localhost\|ManageEngine" 60

    # Focus and maximize
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | \
          grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: \
            -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 1
    fi
}

# Wait for a window with specified title to appear
# Args: $1 - window title pattern (grep pattern)
#       $2 - timeout in seconds (default: 30)
wait_for_window() {
    local window_pattern="$1"
    local timeout=${2:-30}
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | \
                grep -qi "$window_pattern"; then
            echo "Window found after ${elapsed}s" >&2
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "Timeout: Window not found after ${timeout}s" >&2
    return 1
}

# Take a screenshot to /tmp/screenshot.png (or specified path)
# Uses xwd for GNOME compositor (more reliable than scrot/import in GNOME)
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    local WID

    # Get window ID for Firefox (xwd works with specific windows in GNOME compositor)
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool search \
          --class "Firefox" 2>/dev/null | tail -1)

    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
            xwd -id "$WID" -silent -out /tmp/screen.xwd 2>/dev/null && \
        convert /tmp/screen.xwd "$output_file" 2>/dev/null && \
        rm -f /tmp/screen.xwd
    fi

    # Fallback methods
    if [ ! -f "$output_file" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
            scrot "$output_file" 2>/dev/null || \
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
            import -window root "$output_file" 2>/dev/null || true
    fi

    [ -f "$output_file" ] && echo "Screenshot: $output_file" >&2
}

# Query EventLog Analyzer's bundled PostgreSQL database
# Args: $1 - SQL query string
ela_db_query() {
    local query="$1"
    local psql_bin="$ELA_HOME/pgsql/bin/psql"
    local port="33335"

    if [ -f "$psql_bin" ]; then
        "$psql_bin" -h localhost -p "$port" -U eventloganalyzer -d eventlog \
            -t -A -F'|' -c "$query" 2>/dev/null
    else
        # Try alternative database access via su
        su - postgres -c "psql -d eventlog -t -A -F'|' -c \"$query\"" 2>/dev/null || \
        echo "DB_ERROR: Cannot query EventLog Analyzer database"
    fi
}

# Log in to EventLog Analyzer via curl and return cookie jar path
# Returns: path to cookie jar file (used for subsequent API calls)
ela_login() {
    local cookie_jar="${1:-/tmp/ela_session.cookies}"
    curl -s -c "$cookie_jar" \
        --data "j_username=$ADMIN_USER&j_password=$ADMIN_PASS" \
        -L --max-redirs 5 \
        "$ELA_URL/event/j_security_check" \
        -o /dev/null 2>/dev/null
    echo "$cookie_jar"
}

# Make an API call to EventLog Analyzer
# Args: $1 - URL path (e.g., "/event/api/v1/devices")
#       $2 - method (GET|POST, default GET)
#       $3 - JSON data for POST
ela_api_call() {
    local path="$1"
    local method="${2:-GET}"
    local data="${3:-}"
    local cookie_jar="/tmp/ela_api.cookies"

    ela_login "$cookie_jar" >/dev/null 2>&1

    if [ "$method" = "POST" ]; then
        curl -s -b "$cookie_jar" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "$ELA_URL$path" 2>/dev/null
    else
        curl -s -b "$cookie_jar" \
            "$ELA_URL$path" 2>/dev/null
    fi
}

# Export these functions for use in child scripts
export -f wait_for_eventlog_analyzer
export -f ensure_firefox_on_ela
export -f wait_for_window
export -f take_screenshot
export -f ela_db_query
export -f ela_login
export -f ela_api_call
export -f get_firefox_profile_dir
