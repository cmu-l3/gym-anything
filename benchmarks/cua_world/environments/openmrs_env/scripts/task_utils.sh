#!/bin/bash
# Shared utilities for OpenMRS O3 task setup scripts

OMRS_BASE="http://localhost/openmrs/ws/rest/v1"
AUTH="admin:Admin123"
SPA_URL="http://localhost/openmrs/spa"

# ── OpenMRS REST helpers ───────────────────────────────────────────────────────

omrs_get() {
    curl -s -u "$AUTH" "${OMRS_BASE}${1}" 2>/dev/null
}

omrs_post() {
    curl -s -u "$AUTH" -X POST \
         -H "Content-Type: application/json" \
         -d "$2" \
         "${OMRS_BASE}${1}" 2>/dev/null
}

omrs_delete() {
    curl -s -u "$AUTH" -X DELETE "${OMRS_BASE}${1}" 2>/dev/null
}

# Get a patient's UUID by display name substring
get_patient_uuid() {
    local name="$1"
    omrs_get "/patient?q=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$name'))")&v=default" | \
        python3 -c "import sys,json; r=json.load(sys.stdin); print(r['results'][0]['uuid'] if r.get('results') else '')" 2>/dev/null
}

# Get a patient's person UUID from patient UUID
get_person_uuid() {
    local patient_uuid="$1"
    omrs_get "/patient/$patient_uuid?v=default" | \
        python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('person',{}).get('uuid',''))" 2>/dev/null
}

# Query OpenMRS DB via the backend container
omrs_db_query() {
    local sql="$1"
    # Find the db container (handles both compose project naming variants)
    local DB_CONTAINER
    DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'openmrs.*db|db.*openmrs' | head -1 || true)
    [ -z "$DB_CONTAINER" ] && DB_CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep 'mariadb\|mysql' | head -1 || true)
    [ -z "$DB_CONTAINER" ] && DB_CONTAINER="openmrs_env-db-1"
    docker exec "$DB_CONTAINER" mariadb -u openmrs -popenmrs openmrs -N -e "$sql" 2>/dev/null
}

# ── Firefox / window helpers ───────────────────────────────────────────────────

wait_for_window() {
    local pattern="$1"
    local timeout="${2:-30}"
    local elapsed=0
    echo "Waiting for window: $pattern (${timeout}s max)..."
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            echo "  Window found after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "  WARNING: window '$pattern' not found after ${timeout}s"
    return 1
}

get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1}' | head -1
}

focus_firefox() {
    local WID
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 0.5
    fi
}

ensure_firefox_on_url() {
    local url="${1:-$SPA_URL/login}"

    # Kill any existing firefox for a clean start
    pkill -f firefox 2>/dev/null || true
    sleep 2

    echo "Starting Firefox on $url ..."
    su - ga -c "DISPLAY=:1 firefox '$url' > /tmp/firefox_task.log 2>&1 &"
    sleep 5

    wait_for_window "firefox\|mozilla\|OpenMRS" 30
    focus_firefox
    # Dismiss any Firefox UI dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
}

# Ensure OpenMRS admin is logged in via browser automation
ensure_openmrs_logged_in() {
    local target_url="${1:-$SPA_URL}"

    # Check if already logged in via REST API session
    local auth_check
    auth_check=$(curl -s -u "$AUTH" "${OMRS_BASE}/session" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print('ok' if d.get('authenticated') else 'no')" 2>/dev/null || echo "no")

    # Start Firefox on login page
    pkill -f firefox 2>/dev/null || true
    sleep 2
    echo "Starting Firefox on $SPA_URL/login ..."
    su - ga -c "DISPLAY=:1 firefox '$SPA_URL/login' > /tmp/firefox_task.log 2>&1 &"
    sleep 6

    wait_for_window "firefox\|mozilla\|OpenMRS" 30
    focus_firefox
    sleep 2

    # Type username and click Continue (1920x1080: username field ~996,567, Continue ~996,640)
    DISPLAY=:1 xdotool mousemove 996 567 click 1 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+a 2>/dev/null || true
    DISPLAY=:1 xdotool type --clearmodifiers "admin" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool mousemove 996 640 click 1 2>/dev/null || true
    sleep 3

    # Type password and click Log in (password ~996,569, Log in ~996,641)
    DISPLAY=:1 xdotool mousemove 996 569 click 1 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "Admin123" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool mousemove 996 641 click 1 2>/dev/null || true
    sleep 4

    # Select Outpatient Clinic location (radio button ~849,452) and Confirm (~994,923)
    DISPLAY=:1 xdotool mousemove 849 452 click 1 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool mousemove 994 923 click 1 2>/dev/null || true
    sleep 3

    # Dismiss any "Save password?" dialog
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    echo "  Login complete. Navigating to task URL: $target_url"
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$target_url" 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 4
    focus_firefox
}

take_screenshot() {
    local outfile="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$outfile" 2>/dev/null || \
    DISPLAY=:1 scrot "$outfile" 2>/dev/null || true
    [ -f "$outfile" ] && echo "Screenshot: $outfile" || echo "WARNING: screenshot failed"
}

# ── Ensure OpenMRS Docker services are running ───────────────────────────
# Critical when loading from QEMU checkpoint — Docker containers that were
# running during checkpoint creation are NOT running when restored.
ensure_openmrs_running() {
    # Quick check: is OpenMRS already responding?
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://localhost/openmrs/spa" 2>/dev/null || echo "000")
    if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] || [ "$http_code" = "301" ]; then
        echo "OpenMRS already running (HTTP $http_code)"
        return 0
    fi

    echo "OpenMRS not responding (HTTP $http_code). Starting services..."

    # Ensure Docker daemon is running
    systemctl is-active docker >/dev/null 2>&1 || {
        echo "Starting Docker daemon..."
        systemctl start docker
        sleep 5
    }

    # Start containers
    local OMRS_DIR="/home/ga/openmrs"
    if [ -f "$OMRS_DIR/docker-compose.yml" ]; then
        echo "Starting OpenMRS containers..."
        cd "$OMRS_DIR"
        docker compose up -d 2>&1 || docker-compose up -d 2>&1 || true
        cd - >/dev/null
    else
        echo "ERROR: docker-compose.yml not found at $OMRS_DIR"
        return 1
    fi

    # Wait for backend health (longest to start)
    echo "Waiting for OpenMRS backend..."
    local timeout=300
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        local health
        health=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://localhost/openmrs/ws/rest/v1/session" -u "$AUTH" 2>/dev/null || echo "000")
        if [ "$health" = "200" ] || [ "$health" = "302" ]; then
            echo "OpenMRS backend ready after ${elapsed}s"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo "  Still waiting for OpenMRS backend... ${elapsed}s (HTTP $health)"
        fi
    done

    # Wait for frontend/gateway
    echo "Waiting for OpenMRS frontend..."
    elapsed=0
    while [ "$elapsed" -lt 120 ]; do
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://localhost/openmrs/spa" 2>/dev/null || echo "000")
        if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] || [ "$http_code" = "301" ]; then
            echo "OpenMRS frontend ready after ${elapsed}s (HTTP $http_code)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    echo "WARNING: OpenMRS may not be fully ready"
    return 0
}

# Auto-start services when task_utils.sh is sourced
ensure_openmrs_running

# Export all functions
export -f omrs_get omrs_post omrs_delete omrs_db_query
export -f get_patient_uuid get_person_uuid
export -f wait_for_window get_firefox_window_id focus_firefox ensure_firefox_on_url ensure_openmrs_logged_in
export -f take_screenshot ensure_openmrs_running
