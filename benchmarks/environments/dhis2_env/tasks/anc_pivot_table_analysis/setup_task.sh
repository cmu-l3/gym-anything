#!/bin/bash
# Setup script for ANC Pivot Table Analysis task

echo "=== Setting up ANC Pivot Table Analysis Task ==="

source /workspace/scripts/task_utils.sh

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
INITIAL_VIZ_COUNT=$(dhis2_api "visualizations?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_VIZ_COUNT" > /tmp/initial_visualization_count
echo "Initial visualization count: $INITIAL_VIZ_COUNT"

# Record initial Downloads count
mkdir -p /home/ga/Downloads
INITIAL_DOWNLOAD_COUNT=$(ls /home/ga/Downloads/ 2>/dev/null | wc -l | tr -d ' ')
echo "$INITIAL_DOWNLOAD_COUNT" > /tmp/initial_download_count
echo "Initial Downloads count: $INITIAL_DOWNLOAD_COUNT"

# Check if Desktop directory exists and remove any pre-existing anc analysis file
mkdir -p /home/ga/Desktop
if [ -f /home/ga/Desktop/anc_analysis_notes.txt ]; then
    mv /home/ga/Desktop/anc_analysis_notes.txt /tmp/anc_analysis_notes_backup.txt
    echo "Moved pre-existing anc_analysis_notes.txt to backup"
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
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Files Created ==="
echo "  /tmp/task_start_iso: $TASK_START"
echo "  /tmp/initial_visualization_count: $INITIAL_VIZ_COUNT"
echo "  /tmp/initial_download_count: $INITIAL_DOWNLOAD_COUNT"
echo ""
echo "=== ANC Pivot Table Analysis Task Setup Complete ==="
