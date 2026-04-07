#!/bin/bash
echo "=== Setting up Timeline Maintenance Schedule task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST (before recording timestamp) to prevent false positives
rm -f /home/ga/Desktop/timeline_schedule.json 2>/dev/null || true
rm -f /tmp/timeline_maintenance_schedule_result.json 2>/dev/null || true

# Record task start timestamp AFTER cleanup
date +%s > /tmp/timeline_maintenance_schedule_start_ts
echo "Task start recorded: $(cat /tmp/timeline_maintenance_schedule_start_ts)"

# Record initial timeline count via COSMOS REST API
# GET /openc3-api/timeline/DEFAULT returns array of timeline names
TOKEN=$(get_cosmos_token)
INITIAL_TIMELINES=$(curl -s -H "Authorization: $TOKEN" \
    "$OPENC3_URL/openc3-api/timeline/DEFAULT" 2>/dev/null || echo "[]")
INITIAL_TIMELINE_COUNT=$(echo "$INITIAL_TIMELINES" | jq 'length' 2>/dev/null || echo "0")
echo "Initial timeline count: $INITIAL_TIMELINE_COUNT"
printf '%s' "$INITIAL_TIMELINE_COUNT" > /tmp/timeline_maintenance_schedule_initial_count

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|openc3\|cosmos" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Navigate to COSMOS home (agent discovers Timeline tool on their own)
echo "Navigating to COSMOS home..."
navigate_to_url "$OPENC3_URL"
sleep 5

# Focus and maximize the Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/timeline_maintenance_schedule_start.png

echo "=== Timeline Maintenance Schedule Setup Complete ==="
echo ""
echo "Task: Create a maintenance timeline and activity in COSMOS Timeline tool."
echo "Confirmation must be written to: /home/ga/Desktop/timeline_schedule.json"
echo ""
