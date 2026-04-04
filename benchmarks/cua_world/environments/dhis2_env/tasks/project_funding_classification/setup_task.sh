#!/bin/bash
# Setup script for Project Funding Classification task

echo "=== Setting up Project Funding Classification Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if source fails
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Verify DHIS2 is responsive
echo "Checking DHIS2 health..."
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting for DHIS2... ($i/30)"
    sleep 2
done

# 2. Record Task Start Time
date -Iseconds > /tmp/task_start_iso
date +%s > /tmp/task_start_timestamp
echo "Task start time recorded: $(cat /tmp/task_start_iso)"

# 3. Clean up any previous attempts (optional but good for repeatability)
# Note: Deleting metadata in DHIS2 is complex due to constraints. 
# We simply log existence here to help the verifier distinguish new vs old if needed.
# Realistically, we assume a clean env or that the verifier checks timestamps.

# 4. Prepare Browser
echo "Launching Firefox..."
DHIS2_URL="http://localhost:8080"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &"
    sleep 5
fi

# Wait for window
wait_for_window "firefox\|mozilla\|DHIS" 30

# Focus and Maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="