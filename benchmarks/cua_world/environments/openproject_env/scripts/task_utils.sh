#!/bin/bash
# task_utils.sh — Shared utilities for all openproject_env tasks
# Source this file: source /workspace/scripts/task_utils.sh
# NOTE: Do NOT use set -e / set -u in this file or callers (pattern #25)

XAUTH="/run/user/1000/gdm/Xauthority"
OP_URL="http://localhost:8080"
OP_ADMIN_USER="admin"
OP_ADMIN_PASS="Admin1234!"
OP_CONTAINER="openproject"
# API token file written by setup_openproject.sh (plain token for apikey: auth)
OP_API_TOKEN_FILE="/home/ga/openproject_api_token.txt"

# -----------------------------------------------------------------------
# Screenshot utility (GNOME-safe: xwd + convert)
# -----------------------------------------------------------------------
take_screenshot() {
    local output="${1:-/tmp/screenshot.png}"
    local raw_xwd
    raw_xwd=$(mktemp /tmp/xwd_XXXXXX.xwd)
    DISPLAY=:1 XAUTHORITY="${XAUTH}" xwd -root -silent -out "$raw_xwd" 2>/dev/null \
        && convert "$raw_xwd" "$output" 2>/dev/null \
        || echo "Warning: screenshot failed"
    rm -f "$raw_xwd"
    echo "$output"
}

# -----------------------------------------------------------------------
# OpenProject API helper (uses API token — apikey:<token> format)
# Usage: op_api GET /api/v3/projects
#        op_api POST /api/v3/projects '{"name":"Test","identifier":"test"}'
# -----------------------------------------------------------------------
op_api() {
    local method="${1:-GET}"
    local path="$2"
    local body="${3:-}"
    local api_token
    api_token=$(cat "$OP_API_TOKEN_FILE" 2>/dev/null || echo "")
    local auth
    auth=$(printf 'apikey:%s' "$api_token" | base64 -w0)

    if [ -n "$body" ]; then
        curl -s -L -X "$method" "${OP_URL}${path}" \
            -H "Authorization: Basic $auth" \
            -H "Content-Type: application/json" \
            -d "$body" 2>/dev/null
    else
        curl -s -L -X "$method" "${OP_URL}${path}" \
            -H "Authorization: Basic $auth" 2>/dev/null
    fi
}

# -----------------------------------------------------------------------
# Rails runner inside OpenProject container
# Usage: op_rails "User.count"
# -----------------------------------------------------------------------
op_rails() {
    local code="$1"
    docker exec "$OP_CONTAINER" bash -c "cd /app && bundle exec rails runner \"$code\" 2>/dev/null"
}

# -----------------------------------------------------------------------
# PostgreSQL query inside OpenProject container
# Usage: op_db_query "SELECT COUNT(*) FROM users"
# -----------------------------------------------------------------------
op_db_query() {
    local query="$1"
    docker exec "$OP_CONTAINER" bash -c "
        psql -U openproject -d openproject -t -A -c \"$query\" 2>/dev/null \
        || psql -U app -d openproject -t -A -c \"$query\" 2>/dev/null \
        || su -s /bin/bash postgres -c \"psql -d openproject -t -A -c '$query'\" 2>/dev/null
    " 2>/dev/null
}

# -----------------------------------------------------------------------
# Wait for OpenProject to be reachable
# -----------------------------------------------------------------------
wait_for_openproject() {
    local url="${OP_URL}"
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "301" ]; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "Warning: OpenProject not reachable after ${timeout}s"
    return 1
}

# -----------------------------------------------------------------------
# Launch Firefox (cold start) at a given URL with snap profile.
# -----------------------------------------------------------------------
launch_firefox_to() {
    local url="${1:-http://localhost:8080}"
    local wait_sec="${2:-5}"
    local profile="/home/ga/snap/firefox/common/.mozilla/firefox/openproject.profile"

    # Wait for OpenProject web service to be ready before launching Firefox
    wait_for_openproject || echo "WARNING: OpenProject may not be ready, attempting Firefox launch anyway"

    # Fix snap permissions
    chown -R ga:ga /home/ga/snap/ 2>/dev/null || true

    # Kill any stale Firefox
    pkill -9 -f firefox 2>/dev/null || true
    for i in $(seq 1 10); do
        pgrep -f firefox >/dev/null 2>&1 || break
        sleep 1
    done
    sleep 2

    # Remove lock files and launch Firefox as ga user
    su - ga -c "
        rm -f ${profile}/.parentlock ${profile}/lock 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=${XAUTH} \
        setsid firefox --new-instance \
            -profile ${profile} \
            '${url}' &
    "

    # Wait for Firefox window
    for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
        if DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -l 2>/dev/null | grep -qi "mozilla\|firefox"; then
            echo "Firefox window appeared"
            break
        fi
        sleep 2
    done
    sleep "$wait_sec"

    # Maximize
    DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -r :ACTIVE: \
        -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
}

# -----------------------------------------------------------------------
# Navigate Firefox (already running) to a URL
# -----------------------------------------------------------------------
navigate_to() {
    local url="$1"
    local wait_sec="${2:-3}"

    DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -a "Mozilla Firefox" 2>/dev/null || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key ctrl+l" 2>/dev/null
    sleep 0.3
    su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool type --clearmodifiers '${url}'" 2>/dev/null
    sleep 0.2
    su - ga -c "DISPLAY=:1 XAUTHORITY=${XAUTH} xdotool key Return" 2>/dev/null
    sleep "$wait_sec"
}

# -----------------------------------------------------------------------
# Read seed IDs from the JSON file written by setup_openproject.sh
# Returns the work package ID for a given subject substring in a project
# Usage: get_wp_id "ecommerce-platform" "Elasticsearch"
# -----------------------------------------------------------------------
get_wp_id() {
    local project_identifier="$1"
    local subject_fragment="$2"
    python3 - << PYEOF 2>/dev/null
import json, sys
try:
    with open('/home/ga/openproject_seed_ids.json') as f:
        data = json.load(f)
    for wp in data.get('work_packages', []):
        if wp.get('project_identifier') == '$project_identifier' and '$subject_fragment' in wp.get('subject', ''):
            print(wp['id'])
            sys.exit(0)
except:
    pass
PYEOF
}

# -----------------------------------------------------------------------
# Get project numeric ID from identifier
# -----------------------------------------------------------------------
get_project_id() {
    local identifier="$1"
    python3 - << PYEOF 2>/dev/null
import json, sys
try:
    with open('/home/ga/openproject_seed_ids.json') as f:
        data = json.load(f)
    for p in data.get('projects', []):
        if p.get('identifier') == '$identifier':
            print(p['id'])
            sys.exit(0)
except:
    pass
PYEOF
}

# -----------------------------------------------------------------------
# Maximize Firefox window
# -----------------------------------------------------------------------
maximize_firefox() {
    sleep 1
    DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -r :ACTIVE: \
        -b add,maximized_vert,maximized_horz 2>/dev/null || true
}

export -f take_screenshot
export -f op_api
export -f op_rails
export -f op_db_query
export -f wait_for_openproject
export -f launch_firefox_to
export -f navigate_to
export -f get_wp_id
export -f get_project_id
export -f maximize_firefox
