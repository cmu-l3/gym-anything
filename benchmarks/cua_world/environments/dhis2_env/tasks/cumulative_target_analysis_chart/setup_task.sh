#!/bin/bash
# Setup script for Cumulative Target Analysis Chart task

echo "=== Setting up Cumulative Target Analysis Chart Task ==="

source /workspace/scripts/task_utils.sh

# Inline fallback for API calls
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

# Record initial visualization count
echo "Recording initial visualization count..."
INITIAL_VIZ_COUNT=$(dhis2_api "visualizations?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_VIZ_COUNT" > /tmp/initial_visualization_count

# Check for pre-existing visualization with the target name and delete it to ensure clean state
TARGET_NAME="Bo Malaria Cumulative Analysis 2023"
echo "Checking for existing visualization: '$TARGET_NAME'..."
EXISTING_ID=$(dhis2_api "visualizations?filter=displayName:eq:$TARGET_NAME&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); vs=d.get('visualizations',[]); print(vs[0]['id']) if vs else print('')" 2>/dev/null)

if [ -n "$EXISTING_ID" ]; then
    echo "Found existing visualization ($EXISTING_ID). Deleting..."
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/visualizations/$EXISTING_ID"
fi

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

# Focus Firefox
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Complete ==="