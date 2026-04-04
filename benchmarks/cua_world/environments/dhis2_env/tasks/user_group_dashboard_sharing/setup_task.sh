#!/bin/bash
# Setup script for User Group Dashboard Sharing task

echo "=== Setting up User Group Dashboard Sharing Task ==="

source /workspace/scripts/task_utils.sh

# Fallback API function if utils not loaded
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district -X "${2:-GET}" "http://localhost:8080/api/$1"
    }
fi

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Verify DHIS2 is responsive
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

# 2. Clean up pre-existing objects to ensure clean state
# We want the agent to create them fresh.

echo "Cleaning up any pre-existing User Groups..."
EXISTING_GROUPS=$(dhis2_api "userGroups?filter=name:ilike:Kenema&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; print(' '.join([x['id'] for x in json.load(sys.stdin).get('userGroups', [])]))" 2>/dev/null)

for gid in $EXISTING_GROUPS; do
    echo "Deleting old user group: $gid"
    dhis2_api "userGroups/$gid" "DELETE" >/dev/null 2>&1
done

echo "Cleaning up any pre-existing Dashboards..."
EXISTING_DASHBOARDS=$(dhis2_api "dashboards?filter=name:ilike:Kenema&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; print(' '.join([x['id'] for x in json.load(sys.stdin).get('dashboards', [])]))" 2>/dev/null)

for did in $EXISTING_DASHBOARDS; do
    echo "Deleting old dashboard: $did"
    dhis2_api "dashboards/$did" "DELETE" >/dev/null 2>&1
done

# 3. Record start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# 4. Ensure Firefox is open to the right place
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

wait_for_window "firefox\|mozilla\|DHIS" 30

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="