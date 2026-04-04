#!/bin/bash
# Setup script for Custom Indicator Factor task

echo "=== Setting up Custom Indicator Factor Task ==="

source /workspace/scripts/task_utils.sh

# Fallback API function if not sourced
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

# CLEANUP: Delete any pre-existing metadata from previous runs to ensure clean slate
echo "Checking for pre-existing task metadata..."

# 1. Delete Visualization if exists
VIZ_ID=$(dhis2_api "visualizations?filter=name:eq:OPD+Burden+Analysis+2023&fields=id" 2>/dev/null | jq -r '.visualizations[0].id // empty')
if [ -n "$VIZ_ID" ]; then
    echo "Deleting existing visualization: $VIZ_ID"
    dhis2_api "visualizations/$VIZ_ID" "DELETE" >/dev/null
fi

# 2. Delete Indicator if exists
IND_ID=$(dhis2_api "indicators?filter=name:eq:OPD+Visits+per+10,000&fields=id" 2>/dev/null | jq -r '.indicators[0].id // empty')
if [ -n "$IND_ID" ]; then
    echo "Deleting existing indicator: $IND_ID"
    dhis2_api "indicators/$IND_ID" "DELETE" >/dev/null
fi

# 3. Delete Indicator Type if exists (Factor 10000)
# Check by name
TYPE_ID_NAME=$(dhis2_api "indicatorTypes?filter=name:eq:Per+10,000&fields=id" 2>/dev/null | jq -r '.indicatorTypes[0].id // empty')
if [ -n "$TYPE_ID_NAME" ]; then
    echo "Deleting existing indicator type (by name): $TYPE_ID_NAME"
    dhis2_api "indicatorTypes/$TYPE_ID_NAME" "DELETE" >/dev/null
fi

# Check by factor (in case name is different)
TYPE_ID_FACTOR=$(dhis2_api "indicatorTypes?filter=factor:eq:10000&fields=id" 2>/dev/null | jq -r '.indicatorTypes[0].id // empty')
if [ -n "$TYPE_ID_FACTOR" ] && [ "$TYPE_ID_FACTOR" != "$TYPE_ID_NAME" ]; then
    echo "Deleting existing indicator type (by factor): $TYPE_ID_FACTOR"
    dhis2_api "indicatorTypes/$TYPE_ID_FACTOR" "DELETE" >/dev/null
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

# Wait for window and maximize
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

echo "=== Custom Indicator Factor Task Setup Complete ==="