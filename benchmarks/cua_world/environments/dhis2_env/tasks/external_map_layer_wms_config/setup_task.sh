#!/bin/bash
# Setup script for External Map Layer WMS Config task

echo "=== Setting up External Map Layer Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
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

# CLEANUP: Remove any existing External Map Layer with the target name
echo "Checking for existing External Map Layers..."
EXISTING_LAYER_ID=$(dhis2_api "externalMapLayers?filter=name:eq:Global+Topography+WMS&fields=id" 2>/dev/null | \
    python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('externalMapLayers', [{}])[0].get('id', ''))" 2>/dev/null)

if [ -n "$EXISTING_LAYER_ID" ]; then
    echo "Removing pre-existing layer ID: $EXISTING_LAYER_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/externalMapLayers/$EXISTING_LAYER_ID" > /dev/null
fi

# CLEANUP: Remove any existing Map with the target name
echo "Checking for existing Maps..."
EXISTING_MAP_ID=$(dhis2_api "maps?filter=name:eq:Vegetation+Reference+Map&fields=id" 2>/dev/null | \
    python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('maps', [{}])[0].get('id', ''))" 2>/dev/null)

if [ -n "$EXISTING_MAP_ID" ]; then
    echo "Removing pre-existing map ID: $EXISTING_MAP_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/maps/$EXISTING_MAP_ID" > /dev/null
fi

# Ensure Firefox is running and focused
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    # Navigate home
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

WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Target Layer: Global Topography WMS"
echo "Target Map: Vegetation Reference Map"