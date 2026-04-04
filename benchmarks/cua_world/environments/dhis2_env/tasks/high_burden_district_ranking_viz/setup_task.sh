#!/bin/bash
# Setup script for High Burden District Ranking Visualization task

echo "=== Setting up High Burden District Ranking Visualization Task ==="

source /workspace/scripts/task_utils.sh

# Inline API helper if not present
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
fi

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Wait for DHIS2 to be ready
echo "Checking DHIS2 availability..."
for i in $(seq 1 12); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting for DHIS2... (Attempt $i/12)"
    sleep 10
done

# 2. Clean up previous artifacts
echo "Cleaning up previous artifacts..."
rm -f /home/ga/Desktop/malaria_top10.png

# Check for and delete existing visualization if it exists (to ensure clean slate)
EXISTING_VIZ_ID=$(dhis2_api "visualizations?filter=displayName:ilike:Top%2010%20High%20Burden&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('visualizations', [{}])[0].get('id', ''))" 2>/dev/null)

if [ -n "$EXISTING_VIZ_ID" ]; then
    echo "Removing pre-existing visualization: $EXISTING_VIZ_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/visualizations/$EXISTING_VIZ_ID" > /dev/null
fi

# 3. Record start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
echo "Task start time recorded: $(cat /tmp/task_start_iso)"

# 4. Launch Firefox
echo "Launching Firefox..."
DHIS2_URL="http://localhost:8080"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 10
else
    # If running, open new tab/window
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &"
    sleep 5
fi

# 5. Ensure Window Focus
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Capture initial state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="