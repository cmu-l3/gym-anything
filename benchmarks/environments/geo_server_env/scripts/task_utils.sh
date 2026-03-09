#!/bin/bash
# Shared utility functions for GeoServer tasks

# GeoServer REST API
GS_URL="http://localhost:8080/geoserver"
GS_REST="${GS_URL}/rest"
GS_AUTH="admin:Admin123!"

# Debug log
VERIFIER_DEBUG_LOG="/tmp/verifier_debug.log"

# ============================================================
# REST API query function
# ============================================================
gs_rest_get() {
    local endpoint="$1"
    local result
    result=$(curl -s -u "$GS_AUTH" -H "Accept: application/json" "${GS_REST}/${endpoint}" 2>/dev/null)
    echo "$result"
}

gs_rest_get_xml() {
    local endpoint="$1"
    local result
    result=$(curl -s -u "$GS_AUTH" -H "Accept: application/xml" "${GS_REST}/${endpoint}" 2>/dev/null)
    echo "$result"
}

gs_rest_status() {
    local endpoint="$1"
    curl -s -o /dev/null -w "%{http_code}" -u "$GS_AUTH" "${GS_REST}/${endpoint}" 2>/dev/null
}

# ============================================================
# PostGIS query function
# ============================================================
postgis_query() {
    local query="$1"
    local result
    result=$(docker exec -e PGPASSWORD=geoserver123 gs-postgis psql -U geoserver -h localhost -d gis -t -A -c "$query" 2>&1)
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "DB_ERROR: Query failed with exit code $exit_code" >> "$VERIFIER_DEBUG_LOG"
        echo "DB_ERROR: Query: $query" >> "$VERIFIER_DEBUG_LOG"
        echo ""
        return 1
    fi

    echo "$result"
    return 0
}

# ============================================================
# Screenshot function
# ============================================================
take_screenshot() {
    local output_file="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
    DISPLAY=:1 scrot "$output_file" 2>/dev/null || \
    echo "Warning: Could not take screenshot"

    if [ -f "$output_file" ]; then
        echo "Screenshot saved: $output_file"
    fi
}

# ============================================================
# Window management functions
# ============================================================
wait_for_window() {
    local window_pattern="$1"
    local timeout=${2:-30}
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$window_pattern"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}'
}

focus_firefox() {
    local wid=$(get_firefox_window_id)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        sleep 0.5
        return 0
    fi
    return 1
}

# ============================================================
# GeoServer readiness and login
# ============================================================
verify_geoserver_ready() {
    local timeout=${1:-30}
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${GS_URL}/web/" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

ensure_logged_in() {
    echo "Verifying GeoServer is accessible..."
    if ! verify_geoserver_ready 60; then
        echo "ERROR: GeoServer is not responding. Attempting Docker restart..."
        docker restart gs-app 2>/dev/null || true
        sleep 20
        if ! verify_geoserver_ready 120; then
            echo "FATAL: GeoServer still not responding after restart"
            return 1
        fi
    fi

    # Navigate Firefox to GeoServer web admin
    focus_firefox
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
    sleep 0.3
    DISPLAY=:1 xdotool type --delay 20 'http://localhost:8080/geoserver/web/' 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5

    # Check window title to see if we're on GeoServer
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 || echo "")
    echo "Window title: $WINDOW_TITLE"

    # If we see login indicators, try to log in
    if echo "$WINDOW_TITLE" | grep -qi "login\|log in\|sign in"; then
        echo "Login page detected. Performing automated login..."
        sleep 2

        # GeoServer login form: username field, then password
        DISPLAY=:1 xdotool key Tab 2>/dev/null || true
        sleep 0.2
        DISPLAY=:1 xdotool type --delay 30 'admin' 2>/dev/null || true
        sleep 0.2
        DISPLAY=:1 xdotool key Tab 2>/dev/null || true
        sleep 0.2
        DISPLAY=:1 xdotool type --delay 30 'Admin123!' 2>/dev/null || true
        sleep 0.2
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 5
    fi

    FINAL_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 || echo "")
    if echo "$FINAL_TITLE" | grep -qi "geoserver\|welcome"; then
        echo "Successfully verified: logged into GeoServer"
        return 0
    else
        echo "WARNING: Could not confirm GeoServer login. Window: $FINAL_TITLE"
        DISPLAY=:1 xdotool key F5 2>/dev/null || true
        sleep 5
        return 0
    fi
}

# ============================================================
# GeoServer entity count helpers
# ============================================================
get_workspace_count() {
    local result
    result=$(gs_rest_get "workspaces.json" 2>/dev/null)
    echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); ws=d.get('workspaces',{}).get('workspace',[]); print(len(ws) if isinstance(ws,list) else (1 if ws else 0))" 2>/dev/null || echo "0"
}

get_layer_count() {
    local result
    result=$(gs_rest_get "layers.json" 2>/dev/null)
    echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); ls=d.get('layers',{}).get('layer',[]); print(len(ls) if isinstance(ls,list) else (1 if ls else 0))" 2>/dev/null || echo "0"
}

get_style_count() {
    local result
    result=$(gs_rest_get "styles.json" 2>/dev/null)
    echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); ss=d.get('styles',{}).get('style',[]); print(len(ss) if isinstance(ss,list) else (1 if ss else 0))" 2>/dev/null || echo "0"
}

get_layergroup_count() {
    local result
    result=$(gs_rest_get "layergroups.json" 2>/dev/null)
    echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); lg=d.get('layerGroups',{}).get('layerGroup',[]); print(len(lg) if isinstance(lg,list) else (1 if lg else 0))" 2>/dev/null || echo "0"
}

get_datastore_count() {
    local workspace="${1:-}"
    local result
    if [ -n "$workspace" ]; then
        result=$(gs_rest_get "workspaces/${workspace}/datastores.json" 2>/dev/null)
    else
        # Count across all workspaces
        local total=0
        local workspaces
        workspaces=$(gs_rest_get "workspaces.json" | python3 -c "import sys,json; d=json.load(sys.stdin); ws=d.get('workspaces',{}).get('workspace',[]); [print(w['name']) for w in (ws if isinstance(ws,list) else ([ws] if ws else []))]" 2>/dev/null)
        for ws in $workspaces; do
            local count
            count=$(gs_rest_get "workspaces/${ws}/datastores.json" | python3 -c "import sys,json; d=json.load(sys.stdin); ds=d.get('dataStores',{}).get('dataStore',[]); print(len(ds) if isinstance(ds,list) else (1 if ds else 0))" 2>/dev/null || echo "0")
            total=$((total + count))
        done
        echo "$total"
        return
    fi
    echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); ds=d.get('dataStores',{}).get('dataStore',[]); print(len(ds) if isinstance(ds,list) else (1 if ds else 0))" 2>/dev/null || echo "0"
}

# ============================================================
# JSON utility functions
# ============================================================
json_escape() {
    local str="$1"
    echo "$str" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr -d '\n' | tr -d '\r'
}

safe_write_result() {
    local temp_file="$1"
    local dest="${2:-/tmp/task_result.json}"

    rm -f "$dest" 2>/dev/null || sudo rm -f "$dest" 2>/dev/null || true
    cp "$temp_file" "$dest" 2>/dev/null || sudo cp "$temp_file" "$dest"
    chmod 644 "$dest" 2>/dev/null || sudo chmod 644 "$dest" 2>/dev/null || true
    rm -f "$temp_file"

    echo "Result saved to $dest"
    cat "$dest"
}

# ============================================================
# Result integrity nonce
# ============================================================
generate_result_nonce() {
    local nonce
    nonce=$(head -c 16 /dev/urandom | md5sum | cut -d' ' -f1)
    rm -f /tmp/result_nonce 2>/dev/null || sudo rm -f /tmp/result_nonce 2>/dev/null || true
    echo "$nonce" > /tmp/result_nonce 2>/dev/null || { sudo bash -c "echo '$nonce' > /tmp/result_nonce"; }
    chmod 666 /tmp/result_nonce 2>/dev/null || sudo chmod 666 /tmp/result_nonce 2>/dev/null || true
    echo "$nonce"
}

get_result_nonce() {
    cat /tmp/result_nonce 2>/dev/null || echo ""
}

# ============================================================
# GUI interaction detection via GeoServer access logs
# ============================================================
# Snapshots the GeoServer access log line count at task start.
# At export time, checks new log entries for Wicket form POSTs
# (evidence of GUI interaction) vs REST API POSTs only.

snapshot_access_log() {
    # Save the current line count of the access log
    local logfile
    logfile=$(docker exec gs-app bash -c 'ls -t /usr/local/tomcat/logs/localhost_access_log.*.txt 2>/dev/null | head -1' 2>/dev/null || echo "")
    if [ -n "$logfile" ]; then
        local count
        count=$(docker exec gs-app wc -l < "$logfile" 2>/dev/null || echo "0")
        echo "$count" > /tmp/access_log_snapshot
        echo "$logfile" > /tmp/access_log_file
        echo "Access log snapshot: $count lines in $logfile"
    else
        echo "0" > /tmp/access_log_snapshot
        echo "" > /tmp/access_log_file
        echo "WARNING: No access log found"
    fi
}

check_gui_interaction() {
    # Returns "true" or "false" based on whether Wicket form POSTs
    # (GUI submissions) were detected since the snapshot.
    local snapshot_count
    snapshot_count=$(cat /tmp/access_log_snapshot 2>/dev/null || echo "0")
    local logfile
    logfile=$(cat /tmp/access_log_file 2>/dev/null || echo "")

    if [ -z "$logfile" ]; then
        # No log file tracked — try to find the current one
        logfile=$(docker exec gs-app bash -c 'ls -t /usr/local/tomcat/logs/localhost_access_log.*.txt 2>/dev/null | head -1' 2>/dev/null || echo "")
    fi

    if [ -z "$logfile" ]; then
        echo "false"
        return
    fi

    # Get new log entries since snapshot
    local new_entries
    new_entries=$(docker exec gs-app tail -n +$((snapshot_count + 1)) "$logfile" 2>/dev/null || echo "")

    if [ -z "$new_entries" ]; then
        echo "false"
        return
    fi

    # Check for Wicket form POSTs (GUI interaction evidence)
    # Wicket URLs contain /geoserver/web/ with POST method
    # Forms submit to URLs like /geoserver/web/wicket/bookmarkable/... or /geoserver/web/?...
    local gui_posts
    gui_posts=$(echo "$new_entries" | grep -c '"POST.*/geoserver/web/' 2>/dev/null || echo "0")

    if [ "$gui_posts" -gt 0 ]; then
        echo "true"
    else
        echo "false"
    fi
}

# Export functions for subshells
export -f gs_rest_get
export -f gs_rest_get_xml
export -f gs_rest_status
export -f postgis_query
export -f take_screenshot
export -f wait_for_window
export -f get_firefox_window_id
export -f focus_firefox
export -f verify_geoserver_ready
export -f ensure_logged_in
export -f get_workspace_count
export -f get_layer_count
export -f get_style_count
export -f get_layergroup_count
export -f get_datastore_count
export -f json_escape
export -f safe_write_result
export -f generate_result_nonce
export -f get_result_nonce
export -f snapshot_access_log
export -f check_gui_interaction
