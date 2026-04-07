#!/bin/bash
# Shared utilities for all GNU Health tasks

# ---------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------

# Wait for PostgreSQL to be ready (needed after checkpoint restore)
wait_for_postgres() {
    local max_wait="${1:-60}"
    local elapsed=0
    echo "Waiting for PostgreSQL to be ready..."
    while [ $elapsed -lt $max_wait ]; do
        if su - gnuhealth -c "psql -d health50 -At -c 'SELECT 1'" 2>/dev/null | grep -q '1'; then
            echo "PostgreSQL ready after ${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: PostgreSQL not ready after ${max_wait}s"
    return 1
}

# Execute SQL against the GNU Health PostgreSQL database
gnuhealth_db_query() {
    local query="$1"
    su - gnuhealth -c "psql -d health50 -At -c \"$query\"" 2>/dev/null | sed 's/^[[:space:]]*//' | sed '/^$/d'
}

# Get count from a table with optional WHERE clause
gnuhealth_count() {
    local table="$1"
    local where="${2:-1=1}"
    gnuhealth_db_query "SELECT COUNT(*) FROM ${table} WHERE ${where}" | tr -d '[:space:]'
}

# ---------------------------------------------------------------
# Patient helpers
# ---------------------------------------------------------------

get_patient_count() {
    gnuhealth_count "gnuhealth_patient"
}

patient_exists_by_name() {
    local firstname="$1"
    local lastname="$2"
    local count
    # party_party has separate 'name' (first name) and 'lastname' columns
    count=$(gnuhealth_db_query "SELECT COUNT(*) FROM party_party p JOIN gnuhealth_patient gp ON gp.party = p.id WHERE (p.name ILIKE '%${firstname}%' AND p.lastname ILIKE '%${lastname}%') OR CONCAT(p.name, ' ', COALESCE(p.lastname,'')) ILIKE '%${firstname}%${lastname}%'" | tr -d '[:space:]')
    [ "${count:-0}" -gt 0 ]
}

patient_exists_by_code() {
    local code="$1"
    local count
    count=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient WHERE puid = '${code}'" | tr -d '[:space:]')
    [ "${count:-0}" -gt 0 ]
}

get_patient_id_by_name() {
    local firstname="$1"
    local lastname="$2"
    # Returns gnuhealth_patient.id
    gnuhealth_db_query "SELECT gp.id FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id WHERE pp.name ILIKE '%${firstname}%' AND (pp.lastname ILIKE '%${lastname}%' OR '${lastname}' = '') LIMIT 1" | tr -d '[:space:]'
}

# ---------------------------------------------------------------
# Appointment helpers
# ---------------------------------------------------------------

get_appointment_count() {
    gnuhealth_count "gnuhealth_appointment"
}

appointment_exists() {
    local patient_id="$1"
    local date_str="$2"
    local count
    count=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_appointment WHERE patient = ${patient_id} AND appointment_date::date = '${date_str}'" | tr -d '[:space:]')
    [ "${count:-0}" -gt 0 ]
}

# ---------------------------------------------------------------
# Prescription helpers
# ---------------------------------------------------------------

get_prescription_count() {
    gnuhealth_count "gnuhealth_prescription_order"
}

# ---------------------------------------------------------------
# Lab test helpers
# ---------------------------------------------------------------

get_lab_request_count() {
    gnuhealth_count "gnuhealth_patient_lab_test"
}

# ---------------------------------------------------------------
# Window management
# ---------------------------------------------------------------

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

get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}'
}

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
# Firefox navigation helpers
# ---------------------------------------------------------------

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

ensure_firefox_gnuhealth() {
    local wid
    wid=$(get_firefox_window_id)
    if [ -z "$wid" ]; then
        echo "Firefox not running, starting..."
        su - ga -c "DISPLAY=:1 firefox http://localhost:8000/ &"
        sleep 8
        wait_for_window "firefox\|mozilla" 30
    fi
    focus_firefox
}

# Log into GNU Health via the Sao web interface (Tryton 7.0 two-step login)
# Step 1: Enter username on login page, click LOGIN
# Step 2: Password dialog appears, enter password, click OK
gnuhealth_login_firefox() {
    local database="${1:-health50}"
    local username="${2:-admin}"
    local password="${3:-gnusolidario}"

    ensure_firefox_gnuhealth
    sleep 1

    # Navigate to the login page
    navigate_firefox_to "http://localhost:8000/"
    sleep 8

    # Step 1: Click the username field and type the username
    # Username field center is approximately (995, 384) in 1920x1080
    DISPLAY=:1 xdotool mousemove --sync 995 384
    sleep 0.3
    DISPLAY=:1 xdotool click 1
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+a
    sleep 0.2
    DISPLAY=:1 xdotool type --clearmodifiers --delay 30 "$username"
    sleep 0.5

    # Click the LOGIN button: Tab from username field to button, then Space
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key space
    sleep 3

    # Step 2: Password dialog should now be visible ("Password for <user>")
    # The password input field gets focus automatically; type the password
    DISPLAY=:1 xdotool type --clearmodifiers --delay 30 "$password"
    sleep 0.5

    # Press Enter to submit the password dialog (clicks OK)
    DISPLAY=:1 xdotool key Return
    sleep 8

    # Dismiss Firefox "Save password" prompt if it appears
    DISPLAY=:1 xdotool key Escape
    sleep 1

    echo "Login submitted: database=$database user=$username"
}

# Ensure we are logged into GNU Health.
ensure_gnuhealth_logged_in() {
    local target_url="${1:-http://localhost:8000/}"

    ensure_firefox_gnuhealth
    sleep 1

    # Check if we're already logged in by looking at URL
    # For Sao, after login URL typically changes from / to /#menu
    # Always perform login to guarantee auth state
    echo "Performing login to ensure authentication..."
    gnuhealth_login_firefox "health50" "admin" "gnusolidario"

    # If a specific URL/hash is needed, navigate there
    if [ "$target_url" != "http://localhost:8000/" ]; then
        navigate_firefox_to "$target_url"
        sleep 3
    fi
    echo "Navigated to: $target_url"
}

# ---------------------------------------------------------------
# JSON helpers
# ---------------------------------------------------------------

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    s="${s//$'\t'/\\t}"
    echo "$s"
}

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
