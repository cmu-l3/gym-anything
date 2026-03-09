#!/bin/bash
# Setup script for Data Quality Outlier Review task

echo "=== Setting up Data Quality Outlier Review Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if sourcing fails
if ! type dhis2_query &>/dev/null; then
    dhis2_query() {
        local query="$1"
        docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$query" 2>/dev/null
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
if ! check_dhis2_health; then
    echo "Waiting for DHIS2 to become responsive..."
    sleep 20
fi

# Record task start time (Epoch)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Clear previous artifacts
rm -f /home/ga/Desktop/kailahun_data_quality_report.txt
# We don't delete Downloads generally, but we'll check timestamps later

# Record initial number of follow-up flagged values in the database
# This allows us to detect if the agent actually flagged new items
echo "Recording initial follow-up count..."
INITIAL_FOLLOWUP_COUNT=$(dhis2_query "SELECT COUNT(*) FROM datavalue WHERE followup = true" | tr -d ' ' || echo "0")
echo "$INITIAL_FOLLOWUP_COUNT" > /tmp/initial_followup_count
echo "Initial follow-up count: $INITIAL_FOLLOWUP_COUNT"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    # If running, try to focus it
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
    fi
fi

# Wait for window
wait_for_window "firefox\|mozilla\|DHIS" 15

# Maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="