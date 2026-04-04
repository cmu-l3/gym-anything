#!/bin/bash
# Setup script for Tracked Entity Attribute Pattern Validation task

echo "=== Setting up Task: TEA Pattern Validation ==="

source /workspace/scripts/task_utils.sh

# Fallback definition for API calls
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district -X "$1" "http://localhost:8080/api/$2"
    }
fi

# 1. Wait for DHIS2
echo "Checking DHIS2 health..."
if ! check_dhis2_health; then
    echo "Waiting for DHIS2..."
    sleep 10
fi

# 2. Clean up previous attempts (Idempotency)
echo "Checking for existing 'National PUI' attribute..."
EXISTING_ID=$(dhis2_api "GET" "trackedEntityAttributes?filter=name:eq:National+PUI&fields=id" | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['trackedEntityAttributes'][0]['id']) if d.get('trackedEntityAttributes') else print('')" 2>/dev/null)

if [ -n "$EXISTING_ID" ]; then
    echo "Found existing attribute ($EXISTING_ID). Removing..."
    # Note: If it's assigned to a TET, we might need to remove that association first, 
    # but DHIS2 often blocks deletion if data exists. 
    # For a task environment, we assume no data is entered against it yet or soft delete works.
    dhis2_api "DELETE" "trackedEntityAttributes/$EXISTING_ID" > /dev/null
    sleep 2
fi

# 3. Launch Browser
echo "Launching Firefox..."
DHIS2_URL="http://localhost:8080/dhis-web-commons/security/login.action"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &"
    sleep 5
fi

# 4. Record Start Time
date +%s > /tmp/task_start_timestamp

# 5. Focus Window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Take Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="