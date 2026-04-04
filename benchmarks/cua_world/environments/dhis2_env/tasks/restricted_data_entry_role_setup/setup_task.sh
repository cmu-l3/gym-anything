#!/bin/bash
# Setup script for Restricted Data Entry Role Setup task

echo "=== Setting up Restricted Role Task ==="

source /workspace/scripts/task_utils.sh

# Inline API utility if not present
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
        DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
    }
fi

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
for i in $(seq 1 10); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting for DHIS2... ($i/10)"
    sleep 5
done

# Record task start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# Clean state: Remove the target role if it exists
TARGET_ROLE="Clerk - Entry Only"
echo "Checking for existing role '$TARGET_ROLE'..."
EXISTING_ID=$(dhis2_api "userRoles?filter=name:eq:$TARGET_ROLE&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['userRoles'][0]['id']) if d.get('userRoles') else print('')" 2>/dev/null)

if [ -n "$EXISTING_ID" ]; then
    echo "Removing pre-existing role (ID: $EXISTING_ID)..."
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/userRoles/$EXISTING_ID" > /dev/null
    echo "Role removed."
else
    echo "No pre-existing role found. Environment clean."
fi

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 3
fi

# Wait for window
for i in $(seq 1 10); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|DHIS"; then
        break
    fi
    sleep 1
done

# Focus and maximize
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="