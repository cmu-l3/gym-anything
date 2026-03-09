#!/bin/bash
# Setup script for Disaggregation Category Setup task

echo "=== Setting up Disaggregation Category Setup Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify DHIS2 is running and responsive
echo "Checking DHIS2 health..."
if ! check_dhis2_health; then
    echo "Waiting for DHIS2 to become ready..."
    for i in {1..12}; do
        if check_dhis2_health; then
            break
        fi
        sleep 5
    done
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
echo "Task start time: $(cat /tmp/task_start_iso)"

# Clean up any previous attempts (idempotency)
# We search for existing objects with these names and delete them to ensure a clean start
echo "Cleaning up any pre-existing task artifacts..."

# Define cleanup function using API
cleanup_dhis2_object() {
    local type=$1
    local name_filter=$2
    
    # Find IDs
    IDS=$(dhis2_api "$type?filter=name:ilike:$name_filter&fields=id" | jq -r '.[][].id' 2>/dev/null)
    
    for id in $IDS; do
        if [ -n "$id" ] && [ "$id" != "null" ]; then
            echo "Deleting existing $type: $id"
            curl -s -u admin:district -X DELETE "http://localhost:8080/api/$type/$id" > /dev/null
        fi
    done
}

# Clean in reverse order of dependency
cleanup_dhis2_object "categoryCombos" "Pregnancy"
cleanup_dhis2_object "categories" "Pregnancy"
cleanup_dhis2_object "categoryOptions" "Trimester"

# Ensure Firefox is running and focused
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    # If running, navigate to home to reset state
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

# Focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="