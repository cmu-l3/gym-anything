#!/bin/bash
# Setup script for Malaria Burden Dashboard task

echo "=== Setting up Malaria Burden Dashboard Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Inline fallback definitions in case sourcing fails
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
    }
    dhis2_query() {
        local query="$1"
        docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$query" 2>/dev/null
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

# Record initial dashboard count (baseline)
echo "Recording initial dashboard count..."
INITIAL_DASHBOARD_COUNT=$(dhis2_api "dashboards?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_DASHBOARD_COUNT" > /tmp/initial_dashboard_count
echo "Initial dashboard count: $INITIAL_DASHBOARD_COUNT"

# Record initial visualization count (baseline)
echo "Recording initial visualization count..."
INITIAL_VIZ_COUNT=$(dhis2_api "visualizations?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_VIZ_COUNT" > /tmp/initial_visualization_count
echo "Initial visualization count: $INITIAL_VIZ_COUNT"

# Record initial map count (baseline)
INITIAL_MAP_COUNT=$(dhis2_api "maps?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_MAP_COUNT" > /tmp/initial_map_count
echo "Initial map count: $INITIAL_MAP_COUNT"

# Record ALL existing dashboard IDs so we can detect truly new ones later
echo "Recording initial dashboard IDs..."
dhis2_api "dashboards?fields=id&paging=false" 2>/dev/null | \
    python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    ids = [x['id'] for x in d.get('dashboards', [])]
    print('\n'.join(ids))
except:
    pass
" 2>/dev/null > /tmp/initial_dashboard_ids || echo "" > /tmp/initial_dashboard_ids
INITIAL_ID_COUNT=$(wc -l < /tmp/initial_dashboard_ids 2>/dev/null || echo "0")
echo "Recorded $INITIAL_ID_COUNT initial dashboard IDs"

# Ensure Firefox is running and focused on DHIS2 home page
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080/dhis-web-commons/security/login.action"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    # Navigate to DHIS2 home
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" || true
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
echo "  /tmp/task_start_iso"
echo "  /tmp/initial_dashboard_count: $INITIAL_DASHBOARD_COUNT"
echo "  /tmp/initial_visualization_count: $INITIAL_VIZ_COUNT"
echo "  /tmp/initial_map_count: $INITIAL_MAP_COUNT"
echo "  /tmp/task_start_screenshot.png"
echo ""
echo "=== Malaria Burden Dashboard Task Setup Complete ==="
