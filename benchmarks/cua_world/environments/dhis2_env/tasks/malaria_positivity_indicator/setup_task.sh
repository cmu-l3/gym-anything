#!/bin/bash
# Setup script for Malaria Positivity Indicator task

echo "=== Setting up Malaria Positivity Indicator Task ==="

source /workspace/scripts/task_utils.sh

# Inline fallbacks
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

# Clean up any pre-existing matching items to ensure clean state
echo "Cleaning up pre-existing items..."

# Delete existing indicators with exact name matches to prevent confusion
EXISTING_IND=$(dhis2_api "indicators?filter=name:eq:Malaria+RDT+Positivity+Rate&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['indicators'][0]['id']) if d.get('indicators') else print('')" 2>/dev/null)

if [ -n "$EXISTING_IND" ]; then
    echo "Deleting pre-existing indicator: $EXISTING_IND"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/indicators/$EXISTING_IND" > /dev/null
fi

# Delete existing visualizations with exact name matches
EXISTING_VIZ=$(dhis2_api "visualizations?filter=name:eq:Malaria+RDT+Positivity+by+District+2023&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['visualizations'][0]['id']) if d.get('visualizations') else print('')" 2>/dev/null)

if [ -n "$EXISTING_VIZ" ]; then
    echo "Deleting pre-existing visualization: $EXISTING_VIZ"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/visualizations/$EXISTING_VIZ" > /dev/null
fi

# Ensure Downloads directory exists and is clean of relevant files
mkdir -p /home/ga/Downloads
rm -f /home/ga/Downloads/*.csv /home/ga/Downloads/*.xls* 2>/dev/null || true

# Record initial counts
INITIAL_IND_COUNT=$(dhis2_api "indicators?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_IND_COUNT" > /tmp/initial_indicator_count

INITIAL_VIZ_COUNT=$(dhis2_api "visualizations?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_VIZ_COUNT" > /tmp/initial_visualization_count

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

# Wait and maximize
for i in $(seq 1 10); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|DHIS"; then
        break
    fi
    sleep 2
done

WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Task Start: $TASK_START"
echo "Initial Indicators: $INITIAL_IND_COUNT"
echo "Initial Visualizations: $INITIAL_VIZ_COUNT"