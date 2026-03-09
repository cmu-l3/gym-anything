#!/bin/bash
# Setup script for Option Set Referral Tracking task

echo "=== Setting up Option Set Referral Tracking Task ==="

source /workspace/scripts/task_utils.sh

# Inline fallback for API calls if utils not fully loaded
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

# 2. Cleanup: Remove existing metadata if it exists (to ensure clean slate)
echo "Cleaning up any existing task metadata..."

# Find and delete Data Element first (dependency)
DE_ID=$(dhis2_api "dataElements?filter=code:eq:FAC_REF_REASON&fields=id" | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['dataElements'][0]['id'] if d.get('dataElements') else '')" 2>/dev/null)

if [ -z "$DE_ID" ]; then
    # Try finding by name if code didn't match
    DE_ID=$(dhis2_api "dataElements?filter=displayName:ilike:Facility%20Referral%20Reason&fields=id" | \
        python3 -c "import json,sys; d=json.load(sys.stdin); print(d['dataElements'][0]['id'] if d.get('dataElements') else '')" 2>/dev/null)
fi

if [ -n "$DE_ID" ]; then
    echo "Deleting existing Data Element: $DE_ID"
    dhis2_api "dataElements/$DE_ID" "DELETE" > /dev/null
fi

# Find and delete Option Set
OS_ID=$(dhis2_api "optionSets?filter=code:eq:REFERRAL_REASON&fields=id" | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['optionSets'][0]['id'] if d.get('optionSets') else '')" 2>/dev/null)

if [ -z "$OS_ID" ]; then
    OS_ID=$(dhis2_api "optionSets?filter=displayName:ilike:Referral%20Reason&fields=id" | \
        python3 -c "import json,sys; d=json.load(sys.stdin); print(d['optionSets'][0]['id'] if d.get('optionSets') else '')" 2>/dev/null)
fi

if [ -n "$OS_ID" ]; then
    echo "Deleting existing Option Set: $OS_ID"
    dhis2_api "optionSets/$OS_ID" "DELETE" > /dev/null
fi

# 3. Record task start time
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# 4. Launch Browser to Maintenance App
echo "Launching Firefox..."
MAINTENANCE_URL="http://localhost:8080/dhis-web-maintenance/index.html"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$MAINTENANCE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$MAINTENANCE_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

# Wait for window
for i in $(seq 1 10); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|DHIS"; then
        break
    fi
    sleep 2
done

# Maximize
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="