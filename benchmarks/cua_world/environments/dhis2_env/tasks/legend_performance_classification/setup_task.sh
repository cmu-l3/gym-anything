#!/bin/bash
# Setup script for Legend Performance Classification task

echo "=== Setting up Legend Performance Classification Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Inline fallbacks
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
    echo "DHIS2 not ready (HTTP $HTTP_CODE), waiting 10s..."
    sleep 10
done

# Record task start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# Record initial counts to detect new items
echo "Recording baseline counts..."
INITIAL_LEGEND_COUNT=$(dhis2_api "legendSets?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_LEGEND_COUNT" > /tmp/initial_legend_count

INITIAL_VIZ_COUNT=$(dhis2_api "visualizations?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_VIZ_COUNT" > /tmp/initial_viz_count

# Check for pre-existing items with target names and log warning (or delete if safe, but deleting might affect other things in a persistent env)
# For this task, we'll just record IDs to distinguish new ones
echo "Recording existing Legend Set IDs..."
dhis2_api "legendSets?fields=id&paging=false" 2>/dev/null | \
    python3 -c "import json,sys; print('\n'.join([x['id'] for x in json.load(sys.stdin).get('legendSets', [])]))" > /tmp/initial_legend_ids 2>/dev/null || true

echo "Recording existing Visualization IDs..."
dhis2_api "visualizations?fields=id&paging=false" 2>/dev/null | \
    python3 -c "import json,sys; print('\n'.join([x['id'] for x in json.load(sys.stdin).get('visualizations', [])]))" > /tmp/initial_viz_ids 2>/dev/null || true


# Ensure Firefox is running
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080/dhis-web-commons/security/login.action"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

# Wait for Firefox window
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
echo "  /tmp/initial_legend_count: $INITIAL_LEGEND_COUNT"
echo "  /tmp/initial_viz_count: $INITIAL_VIZ_COUNT"
echo ""
echo "=== Legend Performance Classification Task Setup Complete ==="