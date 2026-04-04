#!/bin/bash
# Setup script for Custom Dataset Section Design task

echo "=== Setting up Custom Dataset Section Design Task ==="

source /workspace/scripts/task_utils.sh

# Inline fallback for shared utils
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    check_dhis2_health() {
        local code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info")
        [[ "$code" == "200" || "$code" == "401" ]]
    }
    take_screenshot() {
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Verify DHIS2 is ready
echo "Checking DHIS2 health..."
for i in {1..30}; do
    if check_dhis2_health; then
        echo "DHIS2 is ready."
        break
    fi
    echo "Waiting for DHIS2..."
    sleep 5
done

# 2. Clean up any previous attempts (Idempotency)
# We delete the dataset if it exists to ensure a clean start
echo "Cleaning up previous attempts..."
EXISTING_ID=$(dhis2_api "dataSets?filter=name:eq:Vector%20Control%20Pilot%202024&fields=id" | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['dataSets'][0]['id']) if d.get('dataSets') else print('')")

if [ -n "$EXISTING_ID" ]; then
    echo "Deleting existing dataset $EXISTING_ID..."
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/dataSets/$EXISTING_ID"
fi

# 3. Record Start Time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
echo "Task start time: $(cat /tmp/task_start_iso)"

# 4. Launch Firefox
echo "Launching Firefox..."
DHIS2_URL="http://localhost:8080"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
fi

# 5. Wait for and focus window
wait_for_window "firefox\|mozilla\|DHIS" 30
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="