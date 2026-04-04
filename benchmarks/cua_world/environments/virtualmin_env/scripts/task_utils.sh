#!/bin/bash
# Shared utilities for all Virtualmin environment tasks

# ---------------------------------------------------------------
# Constants
# ---------------------------------------------------------------
VIRTUALMIN_URL="https://localhost:10000"
VIRTUALMIN_USER="root"
VIRTUALMIN_PASS="GymAnything123!"

# ---------------------------------------------------------------
# Virtualmin CLI helpers
# ---------------------------------------------------------------

# List all virtual server domain names
virtualmin_list_domains() {
    virtualmin list-domains --name-only 2>/dev/null || true
}

# Check if a domain exists
virtualmin_domain_exists() {
    local domain="$1"
    virtualmin list-domains --name-only 2>/dev/null | grep -q "^${domain}$"
}

# List email users for a domain
virtualmin_list_users() {
    local domain="$1"
    virtualmin list-users --domain "$domain" 2>/dev/null || true
}

# List email aliases for a domain
virtualmin_list_aliases() {
    local domain="$1"
    virtualmin list-aliases --domain "$domain" 2>/dev/null || true
}

# Check if an email alias exists for a domain
virtualmin_alias_exists() {
    local domain="$1"
    local from="$2"
    virtualmin list-aliases --domain "$domain" 2>/dev/null | grep -q "^${from}@${domain}"
}

# List databases for a domain
virtualmin_list_databases() {
    local domain="$1"
    virtualmin list-domains --domain "$domain" --multiline 2>/dev/null | grep "MySQL database" || true
}

# List DNS records for a domain
virtualmin_list_dns() {
    local domain="$1"
    virtualmin get-dns --domain "$domain" 2>/dev/null || true
}

# Query MariaDB directly
virtualmin_db_query() {
    local query="$1"
    mysql -u root -pGymAnything123! -N -e "$query" 2>/dev/null || true
}

# Check if a MySQL database exists
mysql_database_exists() {
    local dbname="$1"
    local count
    count=$(virtualmin_db_query "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='${dbname}';" | tr -d '[:space:]')
    [ "${count:-0}" -gt 0 ]
}

# Get numeric domain ID for a domain name (needed for Virtualmin 8.x URLs)
# Usage: get_domain_id "acmecorp.test"
get_domain_id() {
    local domain="$1"
    virtualmin list-domains --domain "$domain" --id-only 2>/dev/null | head -1 | tr -d ' '
}

# ---------------------------------------------------------------
# Virtualmin Remote API helpers
# ---------------------------------------------------------------

# Call the Virtualmin remote API
virtualmin_api() {
    local program="$1"
    shift
    local args="program=${program}"
    for arg in "$@"; do
        args="${args}&${arg}"
    done
    curl -sk \
        --user "${VIRTUALMIN_USER}:${VIRTUALMIN_PASS}" \
        "${VIRTUALMIN_URL}/virtual-server/remote.cgi?${args}&json=1" \
        2>/dev/null || true
}

# ---------------------------------------------------------------
# Firefox / GUI automation helpers
# ---------------------------------------------------------------

# Check if Firefox is currently running
firefox_is_running() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iq "firefox\|mozilla"
}

# Wait for Firefox window to appear
wait_for_firefox() {
    local timeout="${1:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if firefox_is_running; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: Firefox did not appear within ${timeout}s"
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
        sleep 0.5
        DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null
        sleep 0.5
        return 0
    fi
    return 1
}

# Navigate Firefox to a URL using Ctrl+L
navigate_to() {
    local url="$1"
    focus_firefox || true
    sleep 1
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers --delay 20 "$url"
    sleep 0.3
    DISPLAY=:1 xdotool key Return
    sleep 4
}

# Dismiss Firefox SSL warning (for self-signed Virtualmin cert)
# On Firefox: "Warning: Potential Security Risk Ahead"
# Click "Advanced..." then "Accept the Risk and Continue"
# Coordinates verified via visual_grounding on 1920x1080 display.
dismiss_ssl_warning() {
    echo "--- Dismissing SSL warning if present ---"
    sleep 2
    # Click "Advanced..." button: actual coords (1318, 705) at 1920x1080
    DISPLAY=:1 xdotool mousemove 1318 705 click 1
    sleep 2
    # Click "Accept the Risk and Continue": actual coords (1251, 1008) at 1920x1080
    DISPLAY=:1 xdotool mousemove 1251 1008 click 1
    sleep 3
}

# Ensure Firefox is open and logged in to Virtualmin
ensure_virtualmin_ready() {
    echo "--- Ensuring Virtualmin is accessible in Firefox ---"

    if ! firefox_is_running; then
        echo "Firefox not running, launching..."
        su - ga -c "DISPLAY=:1 firefox ${VIRTUALMIN_URL} &"
        sleep 10
        wait_for_firefox 30

        # Dismiss SSL warning if this is a fresh launch
        dismiss_ssl_warning

        # Log in
        login_to_virtualmin
    else
        focus_firefox
        sleep 2
        # Navigate to Virtualmin main page; check if we need to log in
        navigate_to "${VIRTUALMIN_URL}/virtual-server/index.cgi"
        sleep 3
        # Check if we ended up on the login page (session expired)
        local title
        title=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || true)
        if echo "$title" | grep -qi "login"; then
            echo "Session expired, logging in again..."
            login_to_virtualmin
        fi
    fi
}

# Log in to Virtualmin via the web UI
# Coordinates verified via visual_grounding on 1920x1080 display:
#   Username field: actual (993, 384)  [VG: 662,256]
#   Password field: actual (993, 426)  [VG: 662,284]
#   Sign In button: actual (993, 511)  [VG: 662,341]
login_to_virtualmin() {
    echo "--- Logging in to Virtualmin ---"
    # Navigate to login page
    navigate_to "${VIRTUALMIN_URL}/"
    sleep 3

    # Username field
    DISPLAY=:1 xdotool mousemove 993 384 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers --delay 30 "${VIRTUALMIN_USER}"

    # Password field (Tab from username)
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers --delay 30 "${VIRTUALMIN_PASS}"

    # Sign In button
    DISPLAY=:1 xdotool mousemove 993 511 click 1
    sleep 8
    echo "--- Login submitted ---"
}

# ---------------------------------------------------------------
# Screenshot helper
# ---------------------------------------------------------------
take_screenshot() {
    local outfile="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$outfile" 2>/dev/null \
        || DISPLAY=:1 import -window root "$outfile" 2>/dev/null \
        || true
}

# ---------------------------------------------------------------
# JSON helper
# ---------------------------------------------------------------
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    echo "$s"
}
