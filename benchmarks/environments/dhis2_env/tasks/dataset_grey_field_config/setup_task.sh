#!/bin/bash
# Setup script for Dataset Grey Field Configuration task

echo "=== Setting up Dataset Grey Field Config Task ==="

source /workspace/scripts/task_utils.sh

# Inline fallback for API
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
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

# Cleanup: Remove artifacts from previous runs if they exist
echo "Cleaning up previous task artifacts..."
# 1. Find and delete the Section
SECTION_ID=$(dhis2_api "sections?filter=name:eq:NCD+Screening+%5BTask%5D&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('sections',[{}])[0].get('id',''))" 2>/dev/null)

if [ -n "$SECTION_ID" ]; then
    echo "Deleting previous section: $SECTION_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/sections/$SECTION_ID" >/dev/null
fi

# 2. Find and delete the Data Element
DE_ID=$(dhis2_api "dataElements?filter=name:eq:Prostate+Screening+%5BTask%5D&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('dataElements',[{}])[0].get('id',''))" 2>/dev/null)

if [ -n "$DE_ID" ]; then
    echo "Deleting previous data element: $DE_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/dataElements/$DE_ID" >/dev/null
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

echo "=== Setup Complete ==="