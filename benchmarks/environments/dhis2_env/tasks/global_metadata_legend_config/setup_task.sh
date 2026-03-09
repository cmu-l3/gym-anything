#!/bin/bash
# Setup script for Global Metadata Legend Configuration

echo "=== Setting up Global Metadata Legend Config Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Verify DHIS2 Health
echo "Checking DHIS2 health..."
for i in $(seq 1 12); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting 5s..."
    sleep 5
done

# 2. Clean State: Remove the Legend Set if it already exists
echo "Cleaning up any existing 'RMNCH Standard Scorecard'..."
EXISTING_LS_ID=$(dhis2_api "legendSets?filter=name:eq:RMNCH%20Standard%20Scorecard&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); ls=d.get('legendSets',[]); print(ls[0]['id']) if ls else print('')")

if [ -n "$EXISTING_LS_ID" ]; then
    echo "Found existing Legend Set ($EXISTING_LS_ID). Deleting..."
    dhis2_api "legendSets/$EXISTING_LS_ID" "DELETE" >/dev/null
else
    echo "Clean state verified."
fi

# 3. Clean State: Unlink the Indicator if it was previously linked to something else
# (Optional, but good for robustness. We won't fully reset the indicator to avoid complexity, 
# but we confirm it exists.)
INDICATOR_CHECK=$(dhis2_api "indicators?filter=name:ilike:Institutional%20delivery%20rate&fields=id" 2>/dev/null | grep -c "id")
if [ "$INDICATOR_CHECK" -eq 0 ]; then
    echo "CRITICAL WARNING: Target indicator 'Institutional delivery rate' not found in database!"
fi

# 4. Record Start Time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
echo "Task start time: $(cat /tmp/task_start_iso)"

# 5. Launch Firefox to Maintenance App
echo "Launching Firefox..."
DHIS2_MAINTENANCE_URL="http://localhost:8080/dhis-web-maintenance/index.html"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_MAINTENANCE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    # If running, open new tab/window
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_MAINTENANCE_URL' > /dev/null 2>&1 &"
    sleep 4
fi

wait_for_window "firefox\|mozilla" 20
focus_window "$(get_firefox_window_id)" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="