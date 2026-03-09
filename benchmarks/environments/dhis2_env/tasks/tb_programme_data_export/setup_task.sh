#!/bin/bash
# Setup script for TB Programme Data Export task

echo "=== Setting up TB Programme Data Export Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Inline fallbacks
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
    }
    dhis2_query() {
        docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$1" 2>/dev/null
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
    echo "DHIS2 not ready (HTTP $HTTP_CODE), waiting 10s..."
    sleep 10
done

# Record task start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# Ensure Downloads directory exists and is clean of pre-existing task-relevant files
mkdir -p /home/ga/Downloads
# Record what's already in Downloads (so we can detect new files)
ls -1t /home/ga/Downloads/ 2>/dev/null | head -20 > /tmp/initial_downloads_list
INITIAL_DOWNLOAD_COUNT=$(ls /home/ga/Downloads/ 2>/dev/null | wc -l | tr -d ' ')
echo "$INITIAL_DOWNLOAD_COUNT" > /tmp/initial_download_count
echo "Initial Downloads file count: $INITIAL_DOWNLOAD_COUNT"

# Record initial visualization count
INITIAL_VIZ_COUNT=$(dhis2_api "visualizations?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_VIZ_COUNT" > /tmp/initial_visualization_count
echo "Initial visualization count: $INITIAL_VIZ_COUNT"

# Check TB programme exists and record metadata
echo "Checking TB programme availability..."
TB_PROG=$(dhis2_api "programs?filter=name:ilike:tb&fields=id,displayName&paging=false" 2>/dev/null | \
    python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    progs = d.get('programs', [])
    if progs:
        print(progs[0].get('displayName', 'TB programme'))
    else:
        print('Not found via API, check DHIS2 directly')
except:
    print('API query failed')
" 2>/dev/null)
echo "TB programme: $TB_PROG" > /tmp/tb_programme_info
echo "TB programme info: $TB_PROG"

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

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Files Created ==="
echo "  /tmp/task_start_timestamp"
echo "  /tmp/task_start_iso: $TASK_START"
echo "  /tmp/initial_download_count: $INITIAL_DOWNLOAD_COUNT"
echo "  /tmp/initial_visualization_count: $INITIAL_VIZ_COUNT"
echo ""
echo "=== TB Programme Data Export Task Setup Complete ==="
