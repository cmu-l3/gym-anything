#!/bin/bash
# Setup script for Longitudinal Weight Loss Alert task

echo "=== Setting up Longitudinal Rule Config Task ==="

source /workspace/scripts/task_utils.sh

# Fallback API function if utils not loaded
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
fi

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
for i in {1..30}; do
    if curl -s "http://localhost:8080/api/system/info" | grep -q "version"; then
        echo "DHIS2 is ready."
        break
    fi
    sleep 2
done

# Record task start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
echo "Task start time: $(cat /tmp/task_start_iso)"

# Identify the Target Program (Child Programme)
echo "Identifying Target Program..."
PROGRAM_JSON=$(dhis2_api "programs?fields=id,displayName&filter=displayName:ilike:Child&paging=false")
PROGRAM_ID=$(echo "$PROGRAM_JSON" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['programs'][0]['id']) if data.get('programs') else print('')")

# Fallback to MNCH if Child Programme not found
if [ -z "$PROGRAM_ID" ]; then
    echo "Child Programme not found, trying MNCH..."
    PROGRAM_JSON=$(dhis2_api "programs?fields=id,displayName&filter=displayName:ilike:MNCH&paging=false")
    PROGRAM_ID=$(echo "$PROGRAM_JSON" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data['programs'][0]['id']) if data.get('programs') else print('')")
fi

if [ -z "$PROGRAM_ID" ]; then
    echo "ERROR: Could not find suitable program. Task may be impossible."
else
    echo "Target Program ID: $PROGRAM_ID"
    echo "$PROGRAM_ID" > /tmp/target_program_id.txt
fi

# Identify Target Data Element (Weight)
echo "Identifying Weight Data Element..."
DE_JSON=$(dhis2_api "dataElements?fields=id,displayName&filter=displayName:ilike:Weight&paging=false")
DE_ID=$(echo "$DE_JSON" | python3 -c "import sys, json; data=json.load(sys.stdin); items=[i for i in data.get('dataElements',[]) if 'weight' in i['displayName'].lower()]; print(items[0]['id']) if items else print('')")

if [ -n "$DE_ID" ]; then
    echo "Target Data Element ID: $DE_ID"
    echo "$DE_ID" > /tmp/target_data_element_id.txt
fi

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080/dhis-web-maintenance/#/list/programSection/program"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

# Focus window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="