#!/bin/bash
# Setup script for Program Indicator Tracker Analytics task

echo "=== Setting up Program Indicator Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
for i in $(seq 1 12); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting for DHIS2... ($i/12)"
    sleep 10
done

# Record task start times
# ISO format for API filters
date -u +"%Y-%m-%dT%H:%M:%S.000" > /tmp/task_start_iso
# Epoch for file mtime checks
date +%s > /tmp/task_start_timestamp

echo "Task start time (ISO): $(cat /tmp/task_start_iso)"

# Record initial program indicator count
INITIAL_PI_COUNT=$(dhis2_api "programIndicators?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_PI_COUNT" > /tmp/initial_pi_count
echo "Initial Program Indicators: $INITIAL_PI_COUNT"

# Record initial last analytics table success time
INITIAL_ANALYTICS_TIME=$(dhis2_api "system/info" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('lastAnalyticsTableSuccess', 'None'))" 2>/dev/null || echo "None")
echo "$INITIAL_ANALYTICS_TIME" > /tmp/initial_analytics_time
echo "Initial Analytics Time: $INITIAL_ANALYTICS_TIME"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 10
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 5
fi

# Maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="