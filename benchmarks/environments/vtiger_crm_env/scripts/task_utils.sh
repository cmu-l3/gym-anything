#!/bin/bash
# Shared utilities for all Vtiger CRM tasks

# ---------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------

# Execute SQL query against Vtiger MariaDB
vtiger_db_query() {
    local query="$1"
    docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -N -e "$query" 2>/dev/null
}

# Get count from a table
vtiger_count() {
    local table="$1"
    local where="${2:-1=1}"
    vtiger_db_query "SELECT COUNT(*) FROM ${table} WHERE ${where}" | tr -d '[:space:]'
}

# ---------------------------------------------------------------
# CRM record helpers
# ---------------------------------------------------------------

# Get contact count
get_contact_count() {
    vtiger_count "vtiger_contactdetails" "1=1"
}

# Get organization count
get_org_count() {
    vtiger_count "vtiger_account" "1=1"
}

# Get deal/potential count
get_deal_count() {
    vtiger_count "vtiger_potential" "1=1"
}

# Get ticket count
get_ticket_count() {
    vtiger_count "vtiger_troubletickets" "1=1"
}

# Get calendar event count
get_event_count() {
    vtiger_count "vtiger_activity" "activitytype='Call' OR activitytype='Meeting'"
}

# Check if contact exists by name
contact_exists() {
    local firstname="$1"
    local lastname="$2"
    local count
    count=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_contactdetails WHERE firstname='${firstname}' AND lastname='${lastname}'" | tr -d '[:space:]')
    [ "$count" -gt 0 ]
}

# Check if organization exists by name
org_exists() {
    local name="$1"
    local count
    count=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_account WHERE accountname='${name}'" | tr -d '[:space:]')
    [ "$count" -gt 0 ]
}

# ---------------------------------------------------------------
# Window management
# ---------------------------------------------------------------

# Wait for a window with the given title pattern
wait_for_window() {
    local pattern="$1"
    local timeout="${2:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iq "$pattern"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# Get Firefox window ID
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}'
}

# Focus and maximize Firefox
focus_firefox() {
    local wid
    wid=$(get_firefox_window_id)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null
        DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------
# Screenshot helpers
# ---------------------------------------------------------------

take_screenshot() {
    local outfile="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$outfile" 2>/dev/null || \
    DISPLAY=:1 import -window root "$outfile" 2>/dev/null || true
}

# ---------------------------------------------------------------
# Firefox helpers
# ---------------------------------------------------------------

# Navigate Firefox to a URL using xdotool
navigate_firefox_to() {
    local url="$1"
    focus_firefox
    sleep 1
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+a
    sleep 0.2
    DISPLAY=:1 xdotool type --delay 20 "$url"
    DISPLAY=:1 xdotool key Return
    sleep 3
}

# Ensure Firefox is running and on Vtiger
ensure_firefox_vtiger() {
    local wid
    wid=$(get_firefox_window_id)
    if [ -z "$wid" ]; then
        echo "Firefox not running, starting..."
        su - ga -c "DISPLAY=:1 firefox http://localhost:8000 &"
        sleep 5
        wait_for_window "firefox\|mozilla" 30
    fi
    focus_firefox
}

# Log into Vtiger CRM via the Firefox login page
# Coordinates calibrated for 1920x1080 resolution
vtiger_login_firefox() {
    local username="${1:-admin}"
    local password="${2:-password}"

    ensure_firefox_vtiger
    sleep 1

    # Navigate to the login page
    navigate_firefox_to "http://localhost:8000/"
    sleep 8

    # Click username field (309, 270 in 1280x720 -> 464, 405 in 1920x1080)
    DISPLAY=:1 xdotool mousemove 464 405
    sleep 0.3
    DISPLAY=:1 xdotool click 1
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --delay 30 "$username"
    sleep 0.3

    # Tab to password field (more reliable than coordinate click)
    DISPLAY=:1 xdotool key Tab
    sleep 0.5
    DISPLAY=:1 xdotool type --delay 30 "$password"
    sleep 0.3

    # Press Enter to submit
    DISPLAY=:1 xdotool key Return
    sleep 8

    echo "Login submitted for user: $username"
}

# Ensure we are logged into Vtiger. Always performs login to guarantee auth.
# After login, navigates to the specified module URL.
ensure_vtiger_logged_in() {
    local target_url="${1:-http://localhost:8000/index.php}"

    ensure_firefox_vtiger
    sleep 1

    echo "Performing login to ensure authentication..."
    vtiger_login_firefox "admin" "password"

    # Navigate to the target module URL
    navigate_firefox_to "$target_url"
    sleep 3
    echo "Navigated to: $target_url"
}

# ---------------------------------------------------------------
# JSON helpers
# ---------------------------------------------------------------

# Escape string for JSON
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    s="${s//$'\t'/\\t}"
    echo "$s"
}

# Write result JSON safely
safe_write_result() {
    local filepath="$1"
    local content="$2"
    local TEMP
    TEMP=$(mktemp /tmp/result.XXXXXX.json)
    echo "$content" > "$TEMP"
    rm -f "$filepath" 2>/dev/null || sudo rm -f "$filepath" 2>/dev/null || true
    cp "$TEMP" "$filepath" 2>/dev/null || sudo cp "$TEMP" "$filepath"
    chmod 666 "$filepath" 2>/dev/null || sudo chmod 666 "$filepath" 2>/dev/null || true
    rm -f "$TEMP"
}
