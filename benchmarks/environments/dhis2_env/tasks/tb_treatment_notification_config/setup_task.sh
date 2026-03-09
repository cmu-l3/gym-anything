#!/bin/bash
# Setup script for TB Treatment Notification Config task

echo "=== Setting up TB Notification Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Inline fallback for API if utils fail
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
        DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
    }
fi

# Verify DHIS2 is running
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

# Record task start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# Record initial notification template IDs (to distinguish new ones)
echo "Recording existing notification templates..."
dhis2_api "programNotificationTemplates?fields=id&paging=false" 2>/dev/null | \
    python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ids = [x['id'] for x in d.get('programNotificationTemplates', [])]
    print('\n'.join(ids))
except:
    pass
" > /tmp/initial_notification_ids 2>/dev/null || echo "" > /tmp/initial_notification_ids

INITIAL_COUNT=$(wc -l < /tmp/initial_notification_ids 2>/dev/null || echo "0")
echo "Initial notification count: $INITIAL_COUNT"

# Ensure Firefox is running and pointing to DHIS2
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080/dhis-web-commons/security/login.action"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

# Wait for Firefox window
for i in $(seq 1 10); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|DHIS"; then
        echo "Firefox window found"
        break
    fi
    sleep 2
done

# Focus and maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== TB Notification Task Setup Complete ==="