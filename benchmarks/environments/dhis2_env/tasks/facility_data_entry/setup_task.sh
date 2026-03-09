#!/bin/bash
# Setup script for Facility Data Entry task

echo "=== Setting up Facility Data Entry Task ==="

source /workspace/scripts/task_utils.sh

# Fallback function definitions if sourcing fails
if ! type dhis2_query &>/dev/null; then
    dhis2_query() {
        docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$1" 2>/dev/null
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Wait for DHIS2 to be ready
echo "Checking DHIS2 health..."
for i in {1..30}; do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" | grep -q "200\|401"; then
        echo "DHIS2 is ready."
        break
    fi
    echo "Waiting for DHIS2... ($i/30)"
    sleep 2
done

# 2. Record task start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
echo "Task start time: $(cat /tmp/task_start_iso)"

# 3. Clean slate: Remove any existing data for Ngelehun CHC for Jan 2024
# This ensures the agent must actually enter data, and we don't just find pre-existing data.
# Note: In the demo DB, Ngelehun CHC is usually UID 'DiszpKrYNg8' or similar.
# We look it up dynamically to be safe.

echo "Looking up Ngelehun CHC ID..."
ORG_UNIT_ID=$(dhis2_query "SELECT organisationunitid FROM organisationunit WHERE name ILIKE '%Ngelehun CHC%' LIMIT 1" | tr -d '[:space:]')
PERIOD_ID=$(dhis2_query "SELECT periodid FROM period WHERE iso = '202401' LIMIT 1" | tr -d '[:space:]')

if [ -z "$PERIOD_ID" ]; then
    # Create period if it doesn't exist (unlikely for 202401 in 2.40, but good practice)
    # Since we can't easily create it via SQL without knowing period type IDs, we assume it exists or relies on agent action creating it implicitly via API (which DHIS2 does)
    # For cleanup purposes, if it doesn't exist, there's no data to clean.
    echo "Period 202401 not found in DB yet. No cleanup needed."
else
    if [ -n "$ORG_UNIT_ID" ]; then
        echo "Cleaning existing data for OrgUnit $ORG_UNIT_ID and Period $PERIOD_ID..."
        
        # Delete data values
        dhis2_query "DELETE FROM datavalue WHERE sourceid=$ORG_UNIT_ID AND periodid=$PERIOD_ID"
        
        # Delete completion record
        dhis2_query "DELETE FROM completedatasetregistration WHERE sourceid=$ORG_UNIT_ID AND periodid=$PERIOD_ID"
        
        echo "Cleanup complete."
    else
        echo "WARNING: Could not find Ngelehun CHC organisation unit. Cleanup skipped."
    fi
fi

# 4. Ensure Firefox is running and focused
echo "Launching Firefox..."
DHIS2_URL="http://localhost:8080/dhis-web-commons/security/login.action"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

wait_for_window "firefox" 30
focus_window "firefox"
# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="