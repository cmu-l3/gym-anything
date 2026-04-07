#!/bin/bash
# Setup script for Custom Facility Attributes task

echo "=== Setting up Custom Facility Attributes Task ==="

source /workspace/scripts/task_utils.sh

# Inline API helper just in case
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

# 1. Verify DHIS2 is responsive
echo "Checking DHIS2 health..."
for i in $(seq 1 12); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting for DHIS2... ($i/12)"
    sleep 5
done

# 2. Clean up previous run state (Anti-gaming/Idempotency)
# We need to ensure the attributes don't already exist, or the agent will get an error creating them.
echo "Cleaning up potential pre-existing attributes..."

# Find ID for 'Generator Functional'
ATTR1_ID=$(dhis2_api "attributes?filter=name:eq:Generator+Functional&fields=id" | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['attributes'][0]['id']) if d.get('attributes') else print('')" 2>/dev/null)

if [ -n "$ATTR1_ID" ]; then
    echo "Deleting existing 'Generator Functional' attribute ($ATTR1_ID)..."
    dhis2_api "attributes/$ATTR1_ID" "DELETE" >/dev/null
fi

# Find ID for 'Distance to District Office (km)'
ATTR2_ID=$(dhis2_api "attributes?filter=name:eq:Distance+to+District+Office+(km)&fields=id" | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['attributes'][0]['id']) if d.get('attributes') else print('')" 2>/dev/null)

if [ -n "$ATTR2_ID" ]; then
    echo "Deleting existing 'Distance...' attribute ($ATTR2_ID)..."
    dhis2_api "attributes/$ATTR2_ID" "DELETE" >/dev/null
fi

# 3. Ensure Firefox is open and logged in
DHIS2_URL="http://localhost:8080/dhis-web-commons/security/login.action"
echo "Ensuring Firefox is running..."

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    # Navigate existing Firefox to DHIS2 URL using xdotool (avoids "Close Firefox" dialog)
    DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || DISPLAY=:1 wmctrl -a "firefox" 2>/dev/null || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool key ctrl+l" 2>/dev/null || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers '$DHIS2_URL'" 2>/dev/null || true
    sleep 0.2
    su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
    sleep 4
fi

# 4. Wait for window and maximize
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|DHIS"; then
        break
    fi
    sleep 1
done

WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 5. Record start time
date +%s > /tmp/task_start_timestamp
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="