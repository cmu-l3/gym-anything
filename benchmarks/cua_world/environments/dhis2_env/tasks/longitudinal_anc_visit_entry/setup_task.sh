#!/bin/bash
# Setup script for Longitudinal ANC Visit Entry task

echo "=== Setting up Longitudinal ANC Visit Entry Task ==="

source /workspace/scripts/task_utils.sh

# Inline API helper just in case
dhis2_api_local() {
    curl -s -u admin:district "http://localhost:8080/api/$1"
}

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
if ! check_dhis2_health; then
    echo "DHIS2 not ready, waiting..."
    sleep 10
    check_dhis2_health || echo "Warning: DHIS2 might be slow"
fi

# Record task start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# Clean up any previous "Hawa Jalloh" to avoid ambiguity (Soft cleanup)
# We won't actually delete data as it's risky in shared envs, but we record the 
# count of existing Hawa Jallohs to ignore them.
echo "Counting existing patients named Hawa Jalloh..."
EXISTING_COUNT=$(docker exec dhis2-db psql -U dhis -d dhis2 -t -c "
    SELECT COUNT(DISTINCT tei.trackedentityinstanceid)
    FROM trackedentityinstance tei
    JOIN trackedentityattributevalue teav ON tei.trackedentityinstanceid = teav.trackedentityinstanceid
    WHERE teav.value ILIKE 'Hawa' OR teav.value ILIKE 'Jalloh';
" 2>/dev/null | tr -d ' ' || echo "0")
echo "$EXISTING_COUNT" > /tmp/initial_hawa_count
echo "Existing Hawa/Jalloh matches: $EXISTING_COUNT"

# Ensure Firefox is running and focused on DHIS2
# We start at the Tracker Capture app specifically to save agent time
echo "Starting Firefox at Tracker Capture..."
TRACKER_URL="http://localhost:8080/dhis-web-tracker-capture/index.html"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$TRACKER_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$TRACKER_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

# Wait and focus
wait_for_window "firefox\|mozilla\|DHIS" 20
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="
echo "Goal: Register Hawa Jalloh and enter 3 visits."