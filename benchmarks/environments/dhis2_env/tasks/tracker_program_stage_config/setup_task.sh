#!/bin/bash
# Setup script for Tracker Program Stage Config task

echo "=== Setting up Tracker Program Stage Config Task ==="

source /workspace/scripts/task_utils.sh

# Inline fallback for API
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
for i in $(seq 1 12); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting for DHIS2... ($i/12)"
    sleep 10
done

# Clean up any previous state (Delete the data element if it exists)
echo "Cleaning up potential previous task artifacts..."
EXISTING_DE=$(dhis2_api "dataElements?filter=name:eq:Chlorhexidine+Gel+Applied&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['dataElements'][0]['id']) if d.get('dataElements') else print('')" 2>/dev/null)

if [ -n "$EXISTING_DE" ]; then
    echo "Found existing data element $EXISTING_DE. Attempting to delete..."
    # Note: This might fail if data exists, but in a fresh task environment it should work or be empty
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/dataElements/$EXISTING_DE" > /dev/null
fi

# Record start time
date +%s > /tmp/task_start_timestamp

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

# Focus window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup Complete ==="