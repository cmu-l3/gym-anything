#!/bin/bash
# Setup script for MCH Tracker Relationship Setup task

echo "=== Setting up MCH Tracker Relationship Setup Task ==="

source /workspace/scripts/task_utils.sh

# Define API helper if not present
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Verify DHIS2 is running
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

# 2. Record task start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# 3. Clean up potential pre-existing objects to ensure a fair test
# (In case the task was run previously on the same instance)
echo "Checking for pre-existing metadata..."

# Check and delete pre-existing Attribute
EXISTING_TEA=$(dhis2_api "trackedEntityAttributes?filter=name:ilike:Mother%20Registration&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('trackedEntityAttributes', [{}])[0].get('id', ''))" 2>/dev/null)

if [ -n "$EXISTING_TEA" ]; then
    echo "Removing pre-existing attribute ($EXISTING_TEA)..."
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/trackedEntityAttributes/$EXISTING_TEA" > /dev/null
fi

# Check and delete pre-existing Relationship Type
EXISTING_RT=$(dhis2_api "relationshipTypes?filter=name:ilike:Mother-Child&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('relationshipTypes', [{}])[0].get('id', ''))" 2>/dev/null)

if [ -n "$EXISTING_RT" ]; then
    echo "Removing pre-existing relationship type ($EXISTING_RT)..."
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/relationshipTypes/$EXISTING_RT" > /dev/null
fi

# 4. Record initial counts
INITIAL_TEA_COUNT=$(dhis2_api "trackedEntityAttributes?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
INITIAL_RT_COUNT=$(dhis2_api "relationshipTypes?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")

echo "$INITIAL_TEA_COUNT" > /tmp/initial_tea_count
echo "$INITIAL_RT_COUNT" > /tmp/initial_rt_count
echo "Initial Counts - Attributes: $INITIAL_TEA_COUNT, Relationship Types: $INITIAL_RT_COUNT"

# 5. Launch Firefox to Maintenance App
echo "Launching Firefox..."
DHIS2_MAINTENANCE_URL="http://localhost:8080/dhis-web-maintenance/index.html"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_MAINTENANCE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_MAINTENANCE_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

# Wait for window
for i in $(seq 1 10); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|DHIS"; then
        break
    fi
    sleep 2
done

# Focus and maximize
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="