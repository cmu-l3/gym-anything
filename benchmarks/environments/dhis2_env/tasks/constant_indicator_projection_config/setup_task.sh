#!/bin/bash
# Setup script for Constant Indicator Projection task

echo "=== Setting up Constant Indicator Projection Task ==="

source /workspace/scripts/task_utils.sh

# Inline fallback definitions
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
for i in $(seq 1 6); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting 10s..."
    sleep 10
done

# Record task start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# Clean up any previous attempts (idempotency)
# We search for constants/indicators with "ITN" in name created by admin and try to delete them
# This ensures a clean state if the task is retried
echo "Cleaning up previous 'ITN' metadata..."
dhis2_api "constants?filter=name:ilike:ITN&fields=id" 2>/dev/null | \
    python3 -c "import json, sys; print(' '.join([x['id'] for x in json.load(sys.stdin).get('constants', [])]))" | \
    xargs -n1 -r -I % curl -s -u admin:district -X DELETE "http://localhost:8080/api/constants/%" 2>/dev/null || true

dhis2_api "indicators?filter=name:ilike:ITN&fields=id" 2>/dev/null | \
    python3 -c "import json, sys; print(' '.join([x['id'] for x in json.load(sys.stdin).get('indicators', [])]))" | \
    xargs -n1 -r -I % curl -s -u admin:district -X DELETE "http://localhost:8080/api/indicators/%" 2>/dev/null || true

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

# Wait for window
for i in $(seq 1 10); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|DHIS"; then
        break
    fi
    sleep 2
done

# Maximize
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="