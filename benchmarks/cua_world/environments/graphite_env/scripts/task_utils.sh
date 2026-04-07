#!/bin/bash
# Shared utilities for Graphite environment tasks

# Take a screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Check if Graphite web UI is responding
wait_for_graphite() {
    local timeout="${1:-60}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "Graphite web UI is ready (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "WARNING: Graphite web UI timeout after ${timeout}s"
    return 1
}

# Check if Carbon is accepting data
wait_for_carbon() {
    local timeout="${1:-30}"
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if nc -z localhost 2003 2>/dev/null; then
            echo "Carbon receiver is ready"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: Carbon receiver timeout"
    return 1
}

# Query Graphite Render API for metric data
graphite_query() {
    local target="$1"
    local from="${2:--1h}"
    local format="${3:-json}"
    curl -s "http://localhost/render?target=${target}&from=${from}&format=${format}" 2>/dev/null
}

# Check if a specific metric exists in Graphite
metric_exists() {
    local metric_pattern="$1"
    local result
    result=$(curl -s "http://localhost/metrics/find?query=${metric_pattern}" 2>/dev/null || echo "[]")
    if echo "$result" | python3 -c "import sys,json; data=json.load(sys.stdin); sys.exit(0 if len(data)>0 else 1)" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Get metric count
get_metric_count() {
    curl -s "http://localhost/metrics/index.json" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(len(data))
except:
    print(0)
" 2>/dev/null || echo "0"
}

# Focus and maximize Firefox
focus_firefox() {
    local WID
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|graphite\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        return 0
    fi
    return 1
}

# Navigate Firefox to a specific URL
navigate_firefox_to() {
    local url="$1"
    # Use xdotool to press Ctrl+L (address bar), type URL, press Enter
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "$url"
    sleep 0.3
    DISPLAY=:1 xdotool key Return
    sleep 2
}

# Ensure Graphite environment is ready for a task
ensure_graphite_ready_for_task() {
    local timeout="${1:-120}"

    echo "Checking Graphite readiness..."

    # Check Docker container
    if ! docker ps | grep -q graphite; then
        echo "Graphite container not running, starting..."
        docker start graphite
        sleep 5
    fi

    # Wait for web UI
    wait_for_graphite "$timeout"

    # Wait for Carbon
    wait_for_carbon 30

    # Check for metrics
    local metric_count
    metric_count=$(get_metric_count)
    echo "Available metrics: $metric_count"

    # Ensure Firefox is running
    if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        echo "Firefox not running, starting..."
        su - ga -c "DISPLAY=:1 setsid firefox 'http://localhost/' > /tmp/firefox.log 2>&1 &"
        sleep 5
    fi

    focus_firefox
    echo "Graphite environment is ready for task"
}
