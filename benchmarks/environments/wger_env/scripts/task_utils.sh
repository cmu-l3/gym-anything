#!/bin/bash
# task_utils.sh — Shared utilities for all wger_env tasks
# Source this file: source /workspace/scripts/task_utils.sh
# NOTE: Do NOT use set -e / set -u in this file or callers (pattern #25)

XAUTH="/run/user/1000/gdm/Xauthority"
WGER_URL="http://localhost"
WGER_ADMIN_USER="admin"
WGER_ADMIN_PASS="adminadmin"

# -----------------------------------------------------------------------
# Screenshot utility (GNOME-safe: xwd + convert, NOT scrot/import)
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
# Get wger JWT access token for admin user (via API)
# -----------------------------------------------------------------------
get_wger_token() {
    local token
    token=$(curl -s -L -X POST "${WGER_URL}/api/v2/token" \
        -H 'Content-Type: application/json' \
        -d "{\"username\": \"${WGER_ADMIN_USER}\", \"password\": \"${WGER_ADMIN_PASS}\"}" \
        2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('access',''))" 2>/dev/null)
    echo "$token"
}

# -----------------------------------------------------------------------
# wger API query helper (returns raw JSON)
# Usage: wger_api GET /api/v2/routine/
#        wger_api POST /api/v2/routine/ '{"name": "Test"}'
# -----------------------------------------------------------------------
wger_api() {
    local method="${1:-GET}"
    local path="$2"
    local body="${3:-}"
    local token
    token=$(get_wger_token)

    if [ -n "$body" ]; then
        curl -s -L -X "$method" "${WGER_URL}${path}" \
            -H "Authorization: Bearer ${token}" \
            -H 'Content-Type: application/json' \
            -d "$body" 2>/dev/null
    else
        curl -s -L -X "$method" "${WGER_URL}${path}" \
            -H "Authorization: Bearer ${token}" 2>/dev/null
    fi
}

# -----------------------------------------------------------------------
# Django shell query inside the wger container
# Usage: django_shell "from wger.training.models import Routine; print(Routine.objects.count())"
# -----------------------------------------------------------------------
django_shell() {
    local code="$1"
    docker exec wger-web python3 manage.py shell -c "$code" 2>/dev/null
}

# -----------------------------------------------------------------------
# PostgreSQL query against wger DB
# Usage: db_query "SELECT COUNT(*) FROM auth_user WHERE username='foo'"
# -----------------------------------------------------------------------
db_query() {
    local query="$1"
    docker exec wger-db psql -U wger -d wger -t -A -c "$query" 2>/dev/null
}

# -----------------------------------------------------------------------
# Launch Firefox (cold start) at a given URL, fixing snap permissions.
# Use this in setup_task.sh instead of navigate_to() for reliable startup.
# -----------------------------------------------------------------------
launch_firefox_to() {
    local url="${1:-http://localhost}"
    local wait_sec="${2:-5}"
    local profile="/home/ga/snap/firefox/common/.mozilla/firefox/wger.profile"

    # Fix snap permissions (snap creates version dirs as root)
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

    # Wait for Firefox window to appear (up to 60s)
    local _i
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
# Navigate Firefox to a URL (Firefox must already be running)
# -----------------------------------------------------------------------
navigate_to() {
    local url="$1"
    local wait_sec="${2:-3}"

    # Ensure Firefox is focused
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
# Wait for a wger page to be reachable (HTTP 200/302)
# -----------------------------------------------------------------------
wait_for_wger_page() {
    local url="${WGER_URL}/api/v2/"
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [ "$code" = "200" ] || [ "$code" = "403" ]; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo "Warning: wger not reachable after ${timeout}s"
    return 1
}

# -----------------------------------------------------------------------
# Create a wger routine via API and return its ID
# -----------------------------------------------------------------------
create_routine() {
    local name="$1"
    local description="${2:-}"
    local today end_date result
    today=$(date +%Y-%m-%d)
    end_date=$(date -d "+6 months" +%Y-%m-%d 2>/dev/null || echo "${today}")
    result=$(wger_api POST /api/v2/routine/ \
        "{\"name\": \"${name}\", \"description\": \"${description}\", \"start\": \"${today}\", \"end\": \"${end_date}\"}")
    echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null
}

# -----------------------------------------------------------------------
# Create a training day within a routine via API and return its ID
# -----------------------------------------------------------------------
create_day() {
    local routine_id="$1"
    local day_name="${2:-Day 1}"
    local order="${3:-1}"
    local result
    result=$(wger_api POST /api/v2/day/ \
        "{\"routine\": ${routine_id}, \"name\": \"${day_name}\", \"order\": ${order}}")
    echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null
}

# -----------------------------------------------------------------------
# Create a nutrition plan via API and return its ID
# -----------------------------------------------------------------------
create_nutrition_plan() {
    local description="$1"
    local result
    result=$(wger_api POST /api/v2/nutritionplan/ "{\"description\": \"${description}\"}")
    echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null
}

# -----------------------------------------------------------------------
# Create a meal within a nutrition plan via API and return its ID
# -----------------------------------------------------------------------
create_meal() {
    local plan_id="$1"
    local meal_name="$2"
    local result
    result=$(wger_api POST /api/v2/meal/ \
        "{\"plan\": ${plan_id}, \"name\": \"${meal_name}\"}")
    echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null
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
export -f get_wger_token
export -f wger_api
export -f django_shell
export -f db_query
export -f launch_firefox_to
export -f navigate_to
export -f wait_for_wger_page
export -f create_routine
export -f create_day
export -f create_nutrition_plan
export -f create_meal
export -f maximize_firefox
