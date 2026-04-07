#!/bin/bash
# Shared utilities for NextGen Connect tasks

# ===== Auto-check: wait for NextGen Connect web service on source =====
# This ensures Docker containers are ready after cache restore
echo "Checking NextGen Connect web service readiness..."
for _nc_check_i in $(seq 1 60); do
    _nc_code=$(curl -sk -o /dev/null -w "%{http_code}" -H "X-Requested-With: OpenAPI" -H "Accept: text/plain" https://localhost:8443/api/server/version 2>/dev/null || echo "000")
    _nc_code2=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null || echo "000")
    if [ "$_nc_code" = "200" ] || [ "$_nc_code" = "401" ] || [ "$_nc_code2" = "200" ]; then
        echo "NextGen Connect web service is ready"
        break
    fi
    sleep 2
done

# Screenshot function - use import, NOT scrot (scrot returns cached images)
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Query PostgreSQL database
query_postgres() {
    local query="$1"
    docker exec nextgen-postgres psql -U postgres -d mirthdb -t -A -c "$query" 2>/dev/null
}

# Get channel count from database
get_channel_count() {
    local count
    count=$(query_postgres "SELECT COUNT(*) FROM channel;" 2>/dev/null)
    if [ -z "$count" ] || [ "$count" = "" ]; then
        echo "0"
    else
        echo "$count"
    fi
}

# Get message count for a channel
get_message_count() {
    local channel_id="$1"
    local count
    count=$(query_postgres "SELECT COUNT(*) FROM d_m${channel_id};" 2>/dev/null)
    if [ -z "$count" ] || [ "$count" = "" ]; then
        echo "0"
    else
        echo "$count"
    fi
}

# Check if channel exists by name (case-insensitive)
# Uses parameterized-style escaping to prevent SQL injection
channel_exists() {
    local channel_name="$1"
    # Escape single quotes in channel name
    local safe_name="${channel_name//\'/\'\'}"
    local count
    count=$(query_postgres "SELECT COUNT(*) FROM channel WHERE LOWER(name) LIKE LOWER('%${safe_name}%');" 2>/dev/null)
    [ -n "$count" ] && [ "$count" -gt 0 ] 2>/dev/null
}

# Get channel ID by name
get_channel_id() {
    local channel_name="$1"
    # Escape single quotes in channel name
    local safe_name="${channel_name//\'/\'\'}"
    query_postgres "SELECT id FROM channel WHERE LOWER(name) LIKE LOWER('%${safe_name}%') LIMIT 1;" 2>/dev/null
}

# Get channel deployment status via REST API
get_channel_status_api() {
    local channel_id="$1"
    curl -sk -u admin:admin \
        -H "X-Requested-With: OpenAPI" \
        -H "Accept: application/json" \
        "https://localhost:8443/api/channels/${channel_id}/status" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); s=d.get('dashboardStatus',d); print(s.get('state','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN"
}

# Wait for NextGen Connect API to be ready
wait_for_api() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local code
        code=$(curl -sk -o /dev/null -w "%{http_code}" -H "X-Requested-With: OpenAPI" -H "Accept: text/plain" https://localhost:8443/api/server/version 2>/dev/null)
        if [ "$code" = "200" ] || [ "$code" = "401" ]; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

# Launch Firefox with web service wait
restart_firefox() {
    local url="${1:-http://localhost:8080}"

    # Wait for NextGen Connect API to be ready before launching Firefox
    wait_for_api 120 || echo "WARNING: NextGen Connect may not be ready"

    # Kill any stale Firefox
    pkill -9 -f firefox 2>/dev/null || true
    sleep 3

    su - ga -c "DISPLAY=:1 firefox '$url' > /tmp/firefox.log 2>&1 &"

    # Wait for Firefox window
    local elapsed=0
    while [ $elapsed -lt 30 ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|mirth\|nextgen"; then
            echo "Firefox window detected"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    # Maximize Firefox
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
}

# Call NextGen Connect REST API (JSON)
# CRITICAL: X-Requested-With header is REQUIRED by NextGen Connect 4.x
api_call_json() {
    local method="$1"
    local endpoint="$2"
    local data="$3"

    if [ -z "$data" ]; then
        curl -sk -X "$method" \
            -u admin:admin \
            -H "X-Requested-With: OpenAPI" \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            "https://localhost:8443/api${endpoint}" 2>/dev/null
    else
        curl -sk -X "$method" \
            -u admin:admin \
            -H "X-Requested-With: OpenAPI" \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -d "$data" \
            "https://localhost:8443/api${endpoint}" 2>/dev/null
    fi
}

# Call NextGen Connect REST API (XML)
# CRITICAL: X-Requested-With header is REQUIRED by NextGen Connect 4.x
api_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"

    if [ -z "$data" ]; then
        curl -sk -X "$method" \
            -u admin:admin \
            -H "X-Requested-With: OpenAPI" \
            -H "Accept: application/xml" \
            -H "Content-Type: application/xml" \
            "https://localhost:8443/api${endpoint}" 2>/dev/null
    else
        curl -sk -X "$method" \
            -u admin:admin \
            -H "X-Requested-With: OpenAPI" \
            -H "Accept: application/xml" \
            -H "Content-Type: application/xml" \
            -d "$data" \
            "https://localhost:8443/api${endpoint}" 2>/dev/null
    fi
}

# Get list of all channels via API
get_channels_api() {
    api_call_json GET "/channels" 2>/dev/null
}

# Get channel statistics via API
get_channel_stats_api() {
    local channel_id="$1"
    api_call_json GET "/channels/${channel_id}/statistics" 2>/dev/null
}

# Get dashboard status for all channels
get_dashboard_status() {
    api_call_json GET "/channels/statuses" 2>/dev/null
}

# Export helper - writes JSON with permission handling
write_result_json() {
    local output_file="$1"
    local json_content="$2"

    # Create temp file
    local temp_file
    temp_file=$(mktemp /tmp/result.XXXXXX.json)
    printf '%s' "$json_content" > "$temp_file"

    # Remove old file with fallbacks
    rm -f "$output_file" 2>/dev/null || sudo rm -f "$output_file" 2>/dev/null || true

    # Copy new file with fallbacks
    cp "$temp_file" "$output_file" 2>/dev/null || sudo cp "$temp_file" "$output_file"

    # Set permissions
    chmod 666 "$output_file" 2>/dev/null || sudo chmod 666 "$output_file" 2>/dev/null || true

    # Cleanup temp
    rm -f "$temp_file"
}
