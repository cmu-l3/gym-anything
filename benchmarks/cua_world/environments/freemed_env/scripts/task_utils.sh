#!/bin/bash
# Shared utilities for FreeMED task setup scripts
# FreeMED uses direct LAMP stack (Apache + MySQL + PHP 7.4)
# URL: http://localhost/freemed/ (no port)
# DB: mysql -u freemed -pfreemed freemed (direct, no Docker)

# -----------------------------------------------------------------------
# Window management utilities
# -----------------------------------------------------------------------

# Wait for a window matching a title pattern
# Args: $1 - pattern, $2 - timeout (default 30)
wait_for_window() {
    local pattern="$1"
    local timeout=${2:-30}
    local elapsed=0

    echo "Waiting for window matching '$pattern'..." >&2
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
           wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            echo "Window found after ${elapsed}s" >&2
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "Timeout: window not found after ${timeout}s" >&2
    return 1
}

# Get Firefox window ID
get_firefox_window_id() {
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}'
}

# Focus a window by ID
focus_window() {
    local wid="$1"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$wid" 2>/dev/null || true
    sleep 0.3
}

# Take a screenshot
# Args: $1 - output path (default /tmp/screenshot.png)
take_screenshot() {
    local outfile="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        import -window root "$outfile" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        scrot "$outfile" 2>/dev/null || true
    [ -f "$outfile" ] && echo "Screenshot saved: $outfile" >&2
}

# -----------------------------------------------------------------------
# FreeMED database utilities
# -----------------------------------------------------------------------

# Execute SQL query against FreeMED database (direct LAMP, no Docker)
# Args: $1 - SQL query string
# Returns: query result (stdout)
freemed_query() {
    local query="$1"
    mysql -u freemed -pfreemed freemed -N -e "$query" 2>/dev/null
}

# Get count of patients
get_patient_count() {
    freemed_query "SELECT COUNT(*) FROM patient"
}

# Check if patient exists by name
# Args: $1 - first name, $2 - last name
# Returns: 0 if found, 1 if not
patient_exists() {
    local fname="$1"
    local lname="$2"
    local count
    count=$(freemed_query "SELECT COUNT(*) FROM patient WHERE ptfname='$fname' AND ptlname='$lname'" 2>/dev/null || echo "0")
    [ "${count:-0}" -gt 0 ]
}

# Get patient ID by name
# Args: $1 - first name, $2 - last name
# Returns: patient ID or empty
get_patient_id() {
    local fname="$1"
    local lname="$2"
    freemed_query "SELECT id FROM patient WHERE ptfname='$fname' AND ptlname='$lname' LIMIT 1"
}

# -----------------------------------------------------------------------
# FreeMED browser launch utilities
# -----------------------------------------------------------------------

# Ensure Firefox is running and showing FreeMED
ensure_firefox_running() {
    local url="${1:-http://localhost/freemed/}"

    if ! pgrep -f firefox > /dev/null 2>&1; then
        echo "Starting Firefox..." >&2
        if [ -x /snap/bin/firefox ]; then
            PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox/freemed.profile"
            rm -f "$PROFILE_DIR/.parentlock" "$PROFILE_DIR/lock" 2>/dev/null || true
            su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
                setsid /snap/bin/firefox --new-instance \
                -profile '$PROFILE_DIR' \
                '$url' > /tmp/firefox_task.log 2>&1 &"
        else
            su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
                setsid firefox '$url' > /tmp/firefox_task.log 2>&1 &"
        fi
        sleep 5
    fi

    wait_for_window "firefox\|mozilla\|FreeMED" 30
}

# Navigate Firefox to a specific URL using xdotool
# Args: $1 - URL
navigate_to() {
    local url="$1"
    local wid
    wid=$(get_firefox_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
        sleep 0.5
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
            xdotool key --window "$wid" ctrl+l 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
            xdotool type --window "$wid" "$url" 2>/dev/null || true
        sleep 0.2
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
            xdotool key --window "$wid" Return 2>/dev/null || true
    fi
}

# Export all functions
export -f wait_for_window
export -f get_firefox_window_id
export -f focus_window
export -f take_screenshot
export -f freemed_query
export -f get_patient_count
export -f patient_exists
export -f get_patient_id
export -f ensure_firefox_running
export -f navigate_to
