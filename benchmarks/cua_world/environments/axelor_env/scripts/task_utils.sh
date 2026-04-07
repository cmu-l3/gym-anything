#!/bin/bash
# Shared utilities for Axelor environment tasks

# ── Configuration ─────────────────────────────────────────────────────────
# Read the URL saved by setup_axelor.sh, defaulting to port 80 (aio-erp nginx)
if [ -f /tmp/axelor_url ]; then
    export AXELOR_URL="$(cat /tmp/axelor_url)"
else
    export AXELOR_URL="http://localhost"
fi
export AXELOR_DB_NAME="axelor"
export AXELOR_ADMIN_USER="admin"
export AXELOR_ADMIN_PASS="admin"
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# ── Database Query ────────────────────────────────────────────────────────
axelor_query() {
    local query="$1"
    docker exec -e PGPASSWORD=axelor axelor-app psql -U axelor -d axelor -h localhost -t -A -F'|' -c "$query" 2>/dev/null
}

axelor_query_csv() {
    local query="$1"
    docker exec -e PGPASSWORD=axelor axelor-app psql -U axelor -d axelor -h localhost --csv -t -c "$query" 2>/dev/null
}

# ── REST API Helpers ──────────────────────────────────────────────────────

# Get CSRF token and session cookie
axelor_login() {
    local cookie_jar="${1:-/tmp/axelor_cookies.txt}"
    rm -f "$cookie_jar"

    # Axelor uses session-based auth via /callback
    local response
    response=$(curl -s -c "$cookie_jar" -b "$cookie_jar" \
        -X POST "${AXELOR_URL}/callback" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"${AXELOR_ADMIN_USER}\", \"password\": \"${AXELOR_ADMIN_PASS}\"}" \
        -w "\n%{http_code}" 2>/dev/null)

    local http_code
    http_code=$(echo "$response" | tail -1)
    if [ "$http_code" = "200" ] || [ "$http_code" = "302" ]; then
        echo "API login successful" >&2
        return 0
    fi

    # Fallback: try form-based login
    response=$(curl -s -c "$cookie_jar" -b "$cookie_jar" \
        -X POST "${AXELOR_URL}/login.jsp" \
        -d "username=${AXELOR_ADMIN_USER}&password=${AXELOR_ADMIN_PASS}" \
        -w "\n%{http_code}" 2>/dev/null)

    http_code=$(echo "$response" | tail -1)
    if [ "$http_code" = "200" ] || [ "$http_code" = "302" ]; then
        echo "Form login successful" >&2
        return 0
    fi

    echo "Login failed (HTTP ${http_code})" >&2
    return 1
}

# Create a record via REST API
axelor_create() {
    local model="$1"
    local json_data="$2"
    local cookie_jar="${3:-/tmp/axelor_cookies.txt}"

    curl -s -b "$cookie_jar" -c "$cookie_jar" \
        -X PUT "${AXELOR_URL}/ws/rest/${model}" \
        -H "Content-Type: application/json" \
        -d "{\"data\": ${json_data}}" 2>/dev/null
}

# Search for records via REST API
axelor_search() {
    local model="$1"
    local domain="$2"
    local fields="$3"
    local cookie_jar="${4:-/tmp/axelor_cookies.txt}"

    local body="{\"offset\": 0, \"limit\": 40"
    if [ -n "$domain" ]; then
        body="${body}, \"domain\": \"${domain}\""
    fi
    if [ -n "$fields" ]; then
        body="${body}, \"fields\": ${fields}"
    fi
    body="${body}}"

    curl -s -b "$cookie_jar" -c "$cookie_jar" \
        -X POST "${AXELOR_URL}/ws/rest/${model}/search" \
        -H "Content-Type: application/json" \
        -d "$body" 2>/dev/null
}

# Fetch a single record
axelor_fetch() {
    local model="$1"
    local id="$2"
    local cookie_jar="${3:-/tmp/axelor_cookies.txt}"

    curl -s -b "$cookie_jar" -c "$cookie_jar" \
        -X GET "${AXELOR_URL}/ws/rest/${model}/${id}" \
        -H "Content-Type: application/json" 2>/dev/null
}

# ── Window Management ────────────────────────────────────────────────────

wait_for_window() {
    local pattern="$1"
    local timeout="${2:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "Window matching '$pattern' not found within ${timeout}s" >&2
    return 1
}

focus_window() {
    local pattern="$1"
    local wid
    wid=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i "$pattern" | head -1 | awk '{print $1}')
    if [ -n "$wid" ]; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -ia "$wid" 2>/dev/null
        return 0
    fi
    return 1
}

get_firefox_window_id() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null \
        | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}'
}

# ── Screenshot ────────────────────────────────────────────────────────────
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority import -window root "$output_file" 2>/dev/null \
        || DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot "$output_file" 2>/dev/null \
        || true
}

# ── xdotool Helpers ───────────────────────────────────────────────────────
safe_xdotool() {
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool "$@"
}

safe_xdotool_type() {
    local text="$1"
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool type --clearmodifiers --delay 50 "$text"
}

# ── Firefox Navigation ───────────────────────────────────────────────────

# Navigate Firefox to a URL via the address bar
navigate_to_url() {
    local url="$1"
    focus_window "firefox\|mozilla" || true
    sleep 1
    # Open address bar, clear it, type URL, press Enter
    safe_xdotool key ctrl+l
    sleep 0.5
    safe_xdotool key ctrl+a
    sleep 0.3
    safe_xdotool_type "$url"
    sleep 0.5
    safe_xdotool key Return
    sleep 3
}

# Ensure Axelor is logged in, navigate to target URL
ensure_axelor_logged_in() {
    local target_url="${1:-${AXELOR_URL}/}"

    # Check if Firefox is running
    if ! pgrep -f firefox > /dev/null 2>&1; then
        echo "Firefox not running, launching..." >&2
        # Use sudo -u ga with explicit env vars (snap Firefox doesn't work with su)
        sudo -u ga DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority \
            setsid firefox "${target_url}" > /tmp/firefox.log 2>&1 &
        sleep 10
        wait_for_window "firefox\|mozilla" 30
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 3
    fi

    # Navigate to target URL
    navigate_to_url "$target_url"
    sleep 3

    # Check if we're on the login page (look for login form)
    local page_content
    page_content=$(curl -s "${AXELOR_URL}/" -L 2>/dev/null || echo "")
    if echo "$page_content" | grep -qi "login\|sign.in\|callback"; then
        echo "Login page detected, attempting login via xdotool..." >&2
        navigate_to_url "${AXELOR_URL}/"
        sleep 5
        # The login page has username and password fields
        # Click on username field (approximate center of form)
        safe_xdotool key Tab
        sleep 0.3
        safe_xdotool_type "${AXELOR_ADMIN_USER}"
        sleep 0.3
        safe_xdotool key Tab
        sleep 0.3
        safe_xdotool_type "${AXELOR_ADMIN_PASS}"
        sleep 0.3
        safe_xdotool key Return
        sleep 5
    fi

    # Navigate to final target if not the root
    if [ "$target_url" != "${AXELOR_URL}/" ] && [ "$target_url" != "${AXELOR_URL}" ]; then
        navigate_to_url "$target_url"
        sleep 3
    fi
}

# ── Partner / Contact Counts ─────────────────────────────────────────────

get_partner_count() {
    local count
    count=$(axelor_query "SELECT COUNT(*) FROM base_partner;" | tr -d '[:space:]')
    echo "${count:-0}"
}

get_customer_count() {
    local count
    count=$(axelor_query "SELECT COUNT(*) FROM base_partner WHERE is_customer = true;" | tr -d '[:space:]')
    echo "${count:-0}"
}

partner_exists() {
    local name="$1"
    local count
    count=$(axelor_query "SELECT COUNT(*) FROM base_partner WHERE LOWER(name) = LOWER('${name}');" | tr -d '[:space:]')
    [ "${count:-0}" -gt 0 ]
}

get_partner_by_name() {
    local name="$1"
    axelor_query "SELECT id, name, is_customer, is_supplier FROM base_partner WHERE LOWER(name) LIKE LOWER('%${name}%') LIMIT 1;"
}

# ── Sale Order Counts ────────────────────────────────────────────────────

get_sale_order_count() {
    local count
    count=$(axelor_query "SELECT COUNT(*) FROM sale_sale_order;" | tr -d '[:space:]')
    echo "${count:-0}"
}

# ── Purchase Order Counts ────────────────────────────────────────────────

get_purchase_order_count() {
    local count
    count=$(axelor_query "SELECT COUNT(*) FROM purchase_purchase_order;" | tr -d '[:space:]')
    echo "${count:-0}"
}

echo "task_utils.sh loaded" >&2
