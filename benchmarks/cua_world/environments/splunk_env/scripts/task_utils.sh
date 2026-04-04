#!/bin/bash
# Shared utilities for all Splunk environment tasks

# Splunk credentials
SPLUNK_USER="admin"
SPLUNK_PASS="SplunkAdmin1!"
SPLUNK_API="https://localhost:8089"
SPLUNK_WEB="http://localhost:8000"

# Run a Splunk search via REST API (oneshot mode)
# Usage: splunk_search "index=main | head 10"
splunk_search() {
    local query="$1"
    local output_mode="${2:-json}"
    curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
        "${SPLUNK_API}/services/search/jobs" \
        -d search="search ${query}" \
        -d exec_mode=oneshot \
        -d output_mode="${output_mode}" \
        2>/dev/null
}

# Get Splunk server info
splunk_server_info() {
    curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
        "${SPLUNK_API}/services/server/info?output_mode=json" \
        2>/dev/null
}

# List all indexes
splunk_list_indexes() {
    curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
        "${SPLUNK_API}/services/data/indexes?output_mode=json" \
        2>/dev/null
}

# Get specific index info
splunk_get_index() {
    local index_name="$1"
    curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
        "${SPLUNK_API}/services/data/indexes/${index_name}?output_mode=json" \
        2>/dev/null
}

# List saved searches
splunk_list_saved_searches() {
    curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
        "${SPLUNK_API}/servicesNS/-/-/saved/searches?output_mode=json&count=0" \
        2>/dev/null
}

# Get specific saved search
splunk_get_saved_search() {
    local name="$1"
    curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
        "${SPLUNK_API}/servicesNS/-/-/saved/searches/$(python3 -c "import urllib.parse; print(urllib.parse.quote('$name', safe=''))")?output_mode=json" \
        2>/dev/null
}

# List monitor inputs
splunk_list_monitors() {
    curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
        "${SPLUNK_API}/services/data/inputs/monitor?output_mode=json&count=0" \
        2>/dev/null
}

# List dashboards/views
splunk_list_dashboards() {
    curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
        "${SPLUNK_API}/servicesNS/-/-/data/ui/views?output_mode=json&count=0" \
        2>/dev/null
}

# Count events in an index
splunk_count_events() {
    local index="${1:-*}"
    local result
    result=$(splunk_search "index=${index} | stats count" "json")
    echo "$result" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('results', [])
    if results:
        print(results[0].get('count', '0'))
    else:
        print('0')
except:
    print('0')
" 2>/dev/null
}

# Check if Splunk is running
splunk_is_running() {
    /opt/splunk/bin/splunk status 2>/dev/null | grep -q "splunkd is running"
}

# Take screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Safe JSON write to avoid permission issues
safe_write_json() {
    local temp_file="$1"
    local target_file="$2"
    rm -f "$target_file" 2>/dev/null || sudo rm -f "$target_file" 2>/dev/null || true
    cp "$temp_file" "$target_file" 2>/dev/null || sudo cp "$temp_file" "$target_file"
    chmod 666 "$target_file" 2>/dev/null || sudo chmod 666 "$target_file" 2>/dev/null || true
    rm -f "$temp_file"
}

# Wait for Firefox window
wait_for_firefox() {
    local timeout="${1:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|splunk\|mozilla"; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

# Get Firefox window ID
get_firefox_wid() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|splunk\|mozilla" | head -1 | awk '{print $1}'
}

# Focus and maximize Firefox
focus_firefox() {
    local wid
    wid=$(get_firefox_wid)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
}

# Check if Firefox window is showing Splunk (by checking title)
firefox_shows_splunk() {
    local wid
    wid=$(get_firefox_wid)
    if [ -z "$wid" ]; then
        return 1
    fi

    local title
    title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|splunk\|mozilla" | head -1)
    if echo "$title" | grep -qi "splunk"; then
        return 0
    fi
    return 1
}

# Check if Firefox window exists (even if not showing Splunk in title)
firefox_window_exists() {
    local wid
    wid=$(get_firefox_wid)
    if [ -n "$wid" ]; then
        return 0
    fi
    return 1
}

# BLOCKING function to ensure Firefox is running with Splunk visible
# RETURNS: 0 if Firefox+Splunk verified, 1 if verification FAILED
# This function will NOT return success unless Firefox is confirmed visible
ensure_firefox_with_splunk() {
    local max_attempts="${1:-120}"
    local attempt=0
    local wid
    local verified=false

    echo "=== BLOCKING: Ensuring Firefox shows Splunk before task starts ==="
    echo "=== Timeout: $max_attempts seconds ==="

    # Phase 1: Check if Firefox is already running with Splunk
    wid=$(get_firefox_wid)
    if [ -n "$wid" ]; then
        echo "Firefox window found (wid=$wid), checking if showing Splunk..."
        if firefox_shows_splunk; then
            echo "Firefox already showing Splunk - focusing and maximizing"
            DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null
            sleep 0.5
            DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null
            sleep 1
            verified=true
        fi
    fi

    # Phase 2: If not verified, launch/refresh Firefox and wait
    if [ "$verified" = false ]; then
        wid=$(get_firefox_wid)
        if [ -z "$wid" ]; then
            echo "Firefox not running - launching Firefox with Splunk URL..."
            DISPLAY=:1 firefox --no-remote "${SPLUNK_WEB}" &
            sleep 10
        else
            echo "Firefox running but not showing Splunk - navigating to Splunk..."
            DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null
            sleep 0.5
            DISPLAY=:1 xdotool key ctrl+l 2>/dev/null
            sleep 0.3
            DISPLAY=:1 xdotool type --clearmodifiers "${SPLUNK_WEB}" 2>/dev/null
            sleep 0.2
            DISPLAY=:1 xdotool key Return 2>/dev/null
            sleep 5
        fi

        # Wait for Splunk to appear in title
        echo "Waiting for Splunk to load in Firefox..."
        while [ $attempt -lt $max_attempts ]; do
            wid=$(get_firefox_wid)
            if [ -n "$wid" ]; then
                DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
                DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

                if firefox_shows_splunk; then
                    echo "SUCCESS: Firefox now showing Splunk (attempt $attempt)"
                    verified=true
                    break
                fi
            fi

            attempt=$((attempt + 1))
            if [ $((attempt % 10)) -eq 0 ]; then
                echo "Still waiting... attempt $attempt/$max_attempts"
            fi
            sleep 1
        done
    fi

    # Phase 3: If still not verified, try refresh as last resort
    if [ "$verified" = false ]; then
        echo "WARNING: Splunk not detected after $max_attempts attempts, trying refresh..."
        wid=$(get_firefox_wid)
        if [ -n "$wid" ]; then
            DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null
            sleep 0.5
            DISPLAY=:1 xdotool key F5 2>/dev/null
            sleep 8

            # Final check after refresh - wait another 30 seconds
            local refresh_attempt=0
            while [ $refresh_attempt -lt 30 ]; do
                if firefox_shows_splunk; then
                    echo "SUCCESS: Firefox showing Splunk after refresh"
                    verified=true
                    break
                fi
                refresh_attempt=$((refresh_attempt + 1))
                sleep 1
            done
        fi
    fi

    # Phase 4: Final focus and maximize if we have a window
    wid=$(get_firefox_wid)
    if [ -n "$wid" ]; then
        echo "Final focus and maximize of Firefox window..."
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null
        sleep 0.5
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null
        sleep 1
    fi

    # CRITICAL: Return proper exit code
    if [ "$verified" = true ]; then
        echo "=== VERIFIED: Firefox is showing Splunk ==="
        return 0
    else
        echo "=== CRITICAL FAILURE: Could not verify Splunk in Firefox ==="
        echo "=== Task start state is INVALID ==="
        # RETURN 1 TO INDICATE FAILURE - not 0!
        return 1
    fi
}

# Navigate Firefox to a specific Splunk page
navigate_to_splunk_page() {
    local url="$1"
    local wid

    wid=$(get_firefox_wid)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 xdotool type --clearmodifiers "$url" 2>/dev/null || true
        sleep 0.2
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 3
    fi
}
