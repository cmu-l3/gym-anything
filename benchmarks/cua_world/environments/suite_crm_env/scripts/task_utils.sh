#!/bin/bash
# Shared utilities for all SuiteCRM tasks

# ---------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------

# Execute SQL query against SuiteCRM MariaDB
suitecrm_db_query() {
    local query="$1"
    docker exec suitecrm-db mysql -u suitecrm -psuitecrm_pass suitecrm -N -e "$query" 2>/dev/null
}

# Get count from a table
suitecrm_count() {
    local table="$1"
    local where="${2:-deleted=0}"
    suitecrm_db_query "SELECT COUNT(*) FROM ${table} WHERE ${where}" | tr -d '[:space:]'
}

# ---------------------------------------------------------------
# CRM record helpers
# ---------------------------------------------------------------

# Get account count
get_account_count() {
    suitecrm_count "accounts" "deleted=0"
}

# Get contact count
get_contact_count() {
    suitecrm_count "contacts" "deleted=0"
}

# Get opportunity count
get_opp_count() {
    suitecrm_count "opportunities" "deleted=0"
}

# Get case count
get_case_count() {
    suitecrm_count "cases" "deleted=0"
}

# Get meeting count
get_meeting_count() {
    suitecrm_count "meetings" "deleted=0"
}

# Check if account exists by name
account_exists() {
    local name="$1"
    local count
    count=$(suitecrm_db_query "SELECT COUNT(*) FROM accounts WHERE name='${name}' AND deleted=0" | tr -d '[:space:]')
    [ "$count" -gt 0 ]
}

# Check if contact exists by name
contact_exists() {
    local firstname="$1"
    local lastname="$2"
    local count
    count=$(suitecrm_db_query "SELECT COUNT(*) FROM contacts WHERE first_name='${firstname}' AND last_name='${lastname}' AND deleted=0" | tr -d '[:space:]')
    [ "$count" -gt 0 ]
}

# Check if opportunity exists by name
opp_exists() {
    local name="$1"
    local count
    count=$(suitecrm_db_query "SELECT COUNT(*) FROM opportunities WHERE name='${name}' AND deleted=0" | tr -d '[:space:]')
    [ "$count" -gt 0 ]
}

# Check if case exists by name
case_exists() {
    local name="$1"
    local count
    count=$(suitecrm_db_query "SELECT COUNT(*) FROM cases WHERE name='${name}' AND deleted=0" | tr -d '[:space:]')
    [ "$count" -gt 0 ]
}

# Check if meeting exists by name
meeting_exists() {
    local name="$1"
    local count
    count=$(suitecrm_db_query "SELECT COUNT(*) FROM meetings WHERE name='${name}' AND deleted=0" | tr -d '[:space:]')
    [ "$count" -gt 0 ]
}

# Delete a record by marking deleted=1 (SuiteCRM soft delete)
soft_delete_record() {
    local table="$1"
    local where="$2"
    suitecrm_db_query "UPDATE ${table} SET deleted=1 WHERE ${where}"
}

# ---------------------------------------------------------------
# GUI command helper — runs as ga user to ensure X11 auth works
# ---------------------------------------------------------------

# Run a GUI command as the ga user (needed when script runs as root via sudo)
run_as_ga() {
    if [ "$(whoami)" = "ga" ]; then
        eval "$@"
    else
        su - ga -c "export DISPLAY=:1; $*"
    fi
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

# Navigate Firefox to a URL using xdotool (runs all commands in one shell as ga)
navigate_firefox_to() {
    local url="$1"
    local wait="${2:-8}"
    run_as_ga "wmctrl -a Firefox 2>/dev/null || wmctrl -a Mozilla 2>/dev/null || true; sleep 0.5; xdotool key ctrl+l; sleep 0.5; xdotool key ctrl+a; sleep 0.3; xdotool type --clearmodifiers --delay 20 '$url'; sleep 0.3; xdotool key Return; sleep $wait"
}

# Ensure Firefox is running and on SuiteCRM
ensure_firefox_suitecrm() {
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

# Log into SuiteCRM via the Firefox login page
suitecrm_login_firefox() {
    local username="${1:-admin}"
    local password="${2:-Admin1234!}"

    ensure_firefox_suitecrm
    sleep 1

    # Navigate to the login page
    navigate_firefox_to "http://localhost:8000/" 10

    # Perform login as ga user in a single shell session for reliable xdotool
    # Coordinates calibrated via visual_grounding at 1920x1080:
    # Username=(995,480), Password=(995,539), LOG IN=(995,597)
    run_as_ga "xdotool mousemove 995 480; sleep 0.3; xdotool click 1; sleep 0.5; xdotool click --repeat 3 1; sleep 0.2; xdotool type --clearmodifiers --delay 30 '${username}'; sleep 0.3; xdotool key Tab; sleep 0.5; xdotool type --clearmodifiers --delay 30 '${password}'; sleep 0.3; xdotool mousemove 995 597; sleep 0.3; xdotool click 1; sleep 8"

    echo "Login submitted for user: $username"
}

# Ensure we are logged into SuiteCRM. Always performs login to guarantee auth.
ensure_suitecrm_logged_in() {
    local target_url="${1:-http://localhost:8000/index.php?module=Home&action=index}"

    ensure_firefox_suitecrm
    sleep 1

    echo "Performing login to ensure authentication..."
    suitecrm_login_firefox "admin" "Admin1234!"

    # Navigate to the target module URL (wait 10s for page load)
    navigate_firefox_to "$target_url" 10
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
