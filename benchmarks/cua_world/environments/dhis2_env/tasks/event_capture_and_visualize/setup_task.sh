#!/bin/bash
# Setup script for Event Capture and Visualize task

echo "=== Setting up Event Capture Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    dhis2_query() {
        docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$1" 2>/dev/null
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Verify DHIS2 is ready
echo "Checking DHIS2 health..."
wait_for_dhis2_ready() {
    for i in {1..30}; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
            echo "DHIS2 is ready."
            return 0
        fi
        sleep 5
    done
    echo "DHIS2 not ready."
    return 1
}
wait_for_dhis2_ready

# 2. Record Task Start Time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
echo "Task Start: $(cat /tmp/task_start_iso)"

# 3. Ensure 'Information Campaign' program exists (it's standard in Sierra Leone demo)
# If not, we might need to create it, but for this task we assume standard demo data.
PROG_ID=$(dhis2_api "programs?filter=name:ilike:Information%20Campaign&fields=id" | jq -r '.programs[0].id // empty')
if [ -z "$PROG_ID" ]; then
    echo "WARNING: Information Campaign program not found. Task may be impossible."
else
    echo "Target Program ID: $PROG_ID"
    echo "$PROG_ID" > /tmp/target_program_id
fi

# 4. Record Initial Event Count for this program
if [ -n "$PROG_ID" ]; then
    INITIAL_COUNT=$(dhis2_query "SELECT COUNT(*) FROM programstageinstance psi JOIN program p ON psi.programid = p.programid WHERE p.uid = '$PROG_ID'" | tr -d ' ')
    echo "$INITIAL_COUNT" > /tmp/initial_event_count
    echo "Initial Event Count: $INITIAL_COUNT"
else
    echo "0" > /tmp/initial_event_count
fi

# 5. Launch Firefox
echo "Launching Firefox..."
DHIS2_URL="http://localhost:8080/dhis-web-dashboard/index.html"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox.log 2>&1 &"
    sleep 8
fi

# 6. Maximize Window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

take_screenshot /tmp/task_initial.png
echo "=== Setup Complete ==="