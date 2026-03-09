#!/bin/bash
# Setup script for Dataset Reporting Notifications task

echo "=== Setting up Dataset Reporting Notifications Task ==="

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

# 1. Wait for DHIS2 to be ready
echo "Checking DHIS2 health..."
for i in $(seq 1 12); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting 10s for DHIS2..."
    sleep 10
done

# 2. Record Task Start Time for Anti-Gaming
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# 3. Record Initial State (to detect new creations)
# Count User Groups
INITIAL_UG_COUNT=$(dhis2_api "userGroups?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_UG_COUNT" > /tmp/initial_ug_count

# Count Datasets
INITIAL_DS_COUNT=$(dhis2_api "dataSets?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_DS_COUNT" > /tmp/initial_ds_count

# Count Notification Templates
INITIAL_NT_COUNT=$(dhis2_api "dataSetNotificationTemplates?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_NT_COUNT" > /tmp/initial_nt_count

echo "Baseline counts - UserGroups: $INITIAL_UG_COUNT, DataSets: $INITIAL_DS_COUNT, Notifications: $INITIAL_NT_COUNT"

# 4. Ensure Clean State (Delete if exists from previous run)
# We search by name and delete to ensure the agent actually creates them
echo "Cleaning up any pre-existing task artifacts..."
# Delete dataset if exists
DS_ID=$(dhis2_api "dataSets?filter=name:eq:Ebola+Emergency+Reporting&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['dataSets'][0]['id']) if d.get('dataSets') else print('')")
if [ -n "$DS_ID" ]; then
    echo "Deleting existing dataset $DS_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/dataSets/$DS_ID" >/dev/null
fi

# Delete user group if exists
UG_ID=$(dhis2_api "userGroups?filter=name:eq:Ebola+Response+Team&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['userGroups'][0]['id']) if d.get('userGroups') else print('')")
if [ -n "$UG_ID" ]; then
    echo "Deleting existing user group $UG_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/userGroups/$UG_ID" >/dev/null
fi

# 5. Launch Firefox
echo "Launching Firefox..."
DHIS2_URL="http://localhost:8080"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|DHIS"; then
        break
    fi
    sleep 1
done

# Focus and Maximize
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="