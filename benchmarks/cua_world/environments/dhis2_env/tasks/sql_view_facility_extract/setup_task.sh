#!/bin/bash
# Setup script for SQL View Facility Extract task

echo "=== Setting up SQL View Task ==="

source /workspace/scripts/task_utils.sh

# Define API helper if not present
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Wait for DHIS2
echo "Checking DHIS2 health..."
for i in $(seq 1 12); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting for DHIS2... ($i/12)"
    sleep 5
done

# 2. Prepare environment
# Clear Downloads to ensure we detect new files
rm -rf /home/ga/Downloads/*
mkdir -p /home/ga/Downloads
chown ga:ga /home/ga/Downloads

# 3. Clean up any existing SQL views from previous runs (to ensure clean state)
echo "Cleaning up pre-existing 'Kenema' SQL views..."
dhis2_api "sqlViews?filter=displayName:ilike:Kenema&fields=id" 2>/dev/null | \
python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for v in d.get('sqlViews', []):
        print(v['id'])
except:
    pass
" | while read -r vid; do
    if [ -n "$vid" ]; then
        echo "Deleting SQL View ID: $vid"
        curl -s -u admin:district -X DELETE "http://localhost:8080/api/sqlViews/$vid" >/dev/null
    fi
done

# 4. Record task start
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# 5. Launch Firefox to Maintenance App (helper for the agent)
MAINTENANCE_URL="http://localhost:8080/dhis-web-maintenance/index.html"
echo "Launching Firefox..."

if pgrep -f firefox > /dev/null; then
    pkill -f firefox
    sleep 2
fi

su - ga -c "DISPLAY=:1 firefox '$MAINTENANCE_URL' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|DHIS" 30

# Maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="