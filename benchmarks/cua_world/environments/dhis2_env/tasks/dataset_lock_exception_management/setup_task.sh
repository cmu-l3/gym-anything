#!/bin/bash
# Setup script for Dataset Lock Exception Management task

echo "=== Setting up Dataset Lock Exception Task ==="

source /workspace/scripts/task_utils.sh

# Define API helper if not present
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district -X "${2:-GET}" \
            -H "Content-Type: application/json" \
            "http://localhost:8080/api/$1"
    }
fi

# 1. Verify DHIS2 is healthy
echo "Checking DHIS2 health..."
if ! check_dhis2_health; then
    echo "Waiting for DHIS2..."
    sleep 30
    check_dhis2_health || echo "Warning: DHIS2 might not be fully ready"
fi

# 2. Record Task Start Time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
echo "Task Start Time: $(cat /tmp/task_start_iso)"

# 3. CLEAN STATE: Reset 'Child Health' Dataset Expiry
echo "Resetting Child Health dataset configuration..."
# Get ID for Child Health
DATASET_ID=$(dhis2_api "dataSets?filter=name:eq:Child%20Health&fields=id" | \
    python3 -c "import json,sys; print(json.load(sys.stdin)['dataSets'][0]['id'])" 2>/dev/null)

if [ -n "$DATASET_ID" ]; then
    echo "Found Child Health Dataset ID: $DATASET_ID"
    # Patch expiryDays to 0 (default/unlimited) to ensure agent actually changes it
    dhis2_api "dataSets/$DATASET_ID" "PATCH" -d '{"expiryDays": 0}' > /dev/null
    echo "Reset expiryDays to 0"
else
    echo "ERROR: Could not find Child Health dataset!"
fi

# 4. CLEAN STATE: Remove existing Lock Exceptions for Target
echo "Cleaning existing lock exceptions..."
# Target: OrgUnit Ngelehun CHC, Period 202301, Dataset Child Health
# First, find if any exist
EXISTING_EXCEPTIONS=$(dhis2_api "lockExceptions?filter=period:eq:202301&fields=id,organisationUnit[name],dataSet[name]" | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
ids = []
for le in data.get('lockExceptions', []):
    ou = le.get('organisationUnit', {}).get('name', '')
    ds = le.get('dataSet', {}).get('name', '')
    if 'Ngelehun' in ou and 'Child Health' in ds:
        ids.append(le.get('id'))
print(' '.join(ids))
" 2>/dev/null)

if [ -n "$EXISTING_EXCEPTIONS" ]; then
    for id in $EXISTING_EXCEPTIONS; do
        echo "Deleting pre-existing exception ID: $id"
        dhis2_api "lockExceptions?pe=202301&ds=$DATASET_ID&ou=$(dhis2_api "organisationUnits?filter=name:like:Ngelehun&fields=id" | jq -r '.organisationUnits[0].id')" "DELETE"
        # Note: Delete endpoint for lock exceptions can be tricky in some DHIS2 versions,
        # often requiring specific query params. Alternatively, we just verify creation time later.
    done
fi

# 5. Launch Browser
echo "Launching Firefox..."
DHIS2_URL="http://localhost:8080/dhis-web-commons/security/login.action"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Focus Window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Capture Initial State Evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="