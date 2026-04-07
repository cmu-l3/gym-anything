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

# Wait for EventLog Analyzer to be fully ready (install + service start + password reset).
# Two-phase wait:
#   Phase 1: Wait for the background setup script to write /tmp/ela_service_ready.marker
#            (this ensures install, first start, resetPwd.sh, and restart are all done)
#   Phase 2: Verify HTTP connectivity (in case the marker was written before the restart finishes)
# Uses 900s default to allow for background install + service start (takes up to ~15 min from boot).
# Args: $1 - timeout in seconds (default 900)
wait_for_eventlog_analyzer() {
    local timeout=${1:-900}
    local elapsed=0
    local marker="/tmp/ela_service_ready.marker"
    local ela_url="$ELA_URL/event/index.do"

    echo "Waiting for EventLog Analyzer (timeout: ${timeout}s)..." >&2

    # Phase 1: Wait for service ready marker from background setup script
    echo "  Phase 1: Waiting for service ready marker ($marker)..." >&2
    while [ $elapsed -lt $timeout ]; do
        if [ -f "$marker" ]; then
            local marker_content
            marker_content=$(cat "$marker" 2>/dev/null)
            if [ "$marker_content" = "OK" ]; then
                echo "  Service ready marker found after ${elapsed}s" >&2
                break
            else
                echo "ERROR: Background setup failed (marker: $marker_content)" >&2
                return 1
            fi
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        if [ $((elapsed % 60)) -eq 0 ]; then
            echo "  Still waiting for marker... ${elapsed}s" >&2
        fi
    done

    if [ ! -f "$marker" ]; then
        echo "WARNING: Service ready marker not found after ${timeout}s, continuing anyway..." >&2
    fi

    # Phase 2: Verify HTTP connectivity
    echo "  Phase 2: Verifying HTTP connectivity at $ela_url..." >&2
    local http_elapsed=0
    while [ $http_elapsed -lt 120 ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 5 "$ela_url" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
            echo "EventLog Analyzer ready (HTTP $HTTP_CODE, total wait: $((elapsed + http_elapsed))s)" >&2
            return 0
        fi
        sleep 5
        http_elapsed=$((http_elapsed + 5))
    done

    echo "WARNING: EventLog Analyzer HTTP check failed after additional 120s" >&2
    return 1
}

# Log in to EventLog Analyzer via the browser login form.
# Uses coordinate-based clicks to fill in the login form on a maximized
# 1920x1080 Firefox window. After login, navigates to the target SPA page
# and dismisses the "What's New" dialog.
#
# Tested coordinates (1920x1080, maximized window):
#   Username field:  (997, 510)
#   Password field:  (997, 550)
#   Login button:    (850, 627)
#   What's New X:    (1530, 244)
#
# Args: $1 - target ELA path after login (e.g., "/event/AppsHome.do#/search/index")
ela_browser_login() {
    local target_path="${1:-/event/AppsHome.do#/home/dashboard/0}"
    local target_url="${ELA_URL}${target_path}"

    echo "Logging in to ELA and navigating to $target_url..." >&2

    # Step 1: Start Firefox at the SPA base URL (AppsHome.do).
    # When not authenticated, ELA shows the login form at this URL.
    # Using AppsHome.do (not index.do) avoids the JSON error after login.
    local profile_base
    profile_base=$(get_firefox_profile_dir)

    su - ga -c "
        export DISPLAY=:1
        export XAUTHORITY=/run/user/1000/gdm/Xauthority
        setsid firefox --new-instance \
            -profile '$profile_base/ela.profile' \
            '${ELA_URL}/event/AppsHome.do' \
            > /tmp/firefox_task.log 2>&1 &
    " 2>/dev/null || true
    sleep 12

    # Dismiss any "Firefox already running" or "Profile Missing" dialog
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | \
            grep -qi "close firefox\|already running\|profile missing"; then
        echo "Dismissing Firefox dialog..." >&2
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return
        sleep 3
    fi

    # Wait for Firefox window
    wait_for_window "firefox\|mozilla\|EventLog\|localhost\|ManageEngine" 60

    # Focus and maximize Firefox
    local WID
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | \
          grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: \
            -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 3
    fi

    # Step 2: Fill in login credentials using coordinate clicks.
    # Coordinates are for a maximized 1920x1080 window.
    echo "Submitting login credentials..." >&2

    # Click username field at (997, 510) — triple-click to select any existing text
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 997 510 click --repeat 3 1
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool type --delay 50 "admin"
    sleep 0.5

    # Click password field at (997, 550) — triple-click to select any existing text
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 997 550 click --repeat 3 1
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool type --delay 50 "admin"
    sleep 0.5

    # Click Login button at (850, 627)
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 850 627 click 1

    # Step 3: Wait for login to complete and dashboard to render.
    # The SPA needs time to load all JavaScript modules after login.
    echo "Waiting for dashboard to render after login..." >&2
    sleep 15

    # Verify login succeeded by checking if the window title changed from the login page.
    # If still showing blank or login, wait more.
    local login_wait=0
    while [ $login_wait -lt 30 ]; do
        local TITLE
        TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | \
                grep -i "firefox\|mozilla" | head -1)
        if echo "$TITLE" | grep -qi "ManageEngine\|Eventlog\|EventLog"; then
            echo "Login successful (window: $TITLE)" >&2
            break
        fi
        sleep 3
        login_wait=$((login_wait + 3))
    done

    # Step 4: Dismiss "What's New" dialog if present.
    # Click the X button at (1530, 244) in 1920x1080. If the dialog isn't present,
    # this click lands harmlessly on the dashboard background.
    echo "Dismissing What's New dialog if present..." >&2
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 1530 244 click 1
    sleep 2
    # Also try Escape as fallback
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape
    sleep 2

    # Step 5: Navigate to the target URL via address bar.
    # This changes only the hash route, which the SPA handles client-side without a full reload.
    echo "Navigating to target: $target_url" >&2
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key ctrl+a
    sleep 0.3
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool type --delay 20 "$target_url"
    sleep 0.5
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return
    sleep 10
}

# Ensure Firefox is running and showing EventLog Analyzer.
# Always kills any existing Firefox first, then starts fresh.
# Handles login automatically and navigates to the specified page.
ensure_firefox_on_ela() {
    local ela_path="${1:-/event/AppsHome.do#/home/dashboard/0}"
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

    # Fix snap permissions (post_start may have created dirs as root)
    chown -R ga:ga /home/ga/snap 2>/dev/null || true

    # Use the login flow which starts Firefox, logs in, and navigates to target
    ela_browser_login "$ela_path"

    # Final focus and maximize
    local WID
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
export -f ela_browser_login
export -f ensure_firefox_on_ela
export -f wait_for_window
export -f take_screenshot
export -f ela_db_query
export -f ela_login
export -f ela_api_call
export -f get_firefox_profile_dir
