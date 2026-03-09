#!/bin/bash
# Shared utilities for all Snipe-IT tasks

# ---------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------

# Execute SQL query against Snipe-IT MariaDB
snipeit_db_query() {
    local query="$1"
    docker exec snipeit-db mysql -u snipeit -psnipeit_pass snipeit -N -e "$query" 2>/dev/null
}

# Get count from a table
snipeit_count() {
    local table="$1"
    local where="${2:-1=1}"
    snipeit_db_query "SELECT COUNT(*) FROM ${table} WHERE ${where}" | tr -d '[:space:]'
}

# ---------------------------------------------------------------
# API helpers
# ---------------------------------------------------------------

# Get API token
get_api_token() {
    cat /home/ga/snipeit/api_token.txt 2>/dev/null || echo ""
}

# Make Snipe-IT API call
snipeit_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local token
    token=$(get_api_token)
    curl -s -X "$method" \
        "http://localhost:8000/api/v1/${endpoint}" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${token}" \
        -d "$data" 2>/dev/null
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
    # Focus Firefox
    focus_firefox
    sleep 1
    # Open location bar and type URL
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --delay 20 "$url"
    DISPLAY=:1 xdotool key Return
    sleep 3
}

# Ensure Firefox is running and on Snipe-IT
ensure_firefox_snipeit() {
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

# ---------------------------------------------------------------
# Asset query helpers
# ---------------------------------------------------------------

# Get asset count
get_asset_count() {
    snipeit_count "assets" "deleted_at IS NULL"
}

# Check if asset exists by tag
asset_exists_by_tag() {
    local tag="$1"
    local count
    count=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE asset_tag='${tag}' AND deleted_at IS NULL" | tr -d '[:space:]')
    [ "$count" -gt 0 ]
}

# Get asset data by tag
get_asset_by_tag() {
    local tag="$1"
    snipeit_db_query "SELECT id, asset_tag, name, serial, model_id, status_id, assigned_to, assigned_type, purchase_date, purchase_cost FROM assets WHERE asset_tag='${tag}' AND deleted_at IS NULL LIMIT 1"
}

# Get user count (non-admin)
get_user_count() {
    snipeit_count "users" "deleted_at IS NULL"
}
