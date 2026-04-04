#!/bin/bash
# Setup script for Predictor Threshold Configuration task

echo "=== Setting up Predictor Threshold Configuration Task ==="

source /workspace/scripts/task_utils.sh

# Inline fallback for dhis2_api if sourcing fails or function missing
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

# 1. Verify DHIS2 health
echo "Checking DHIS2 health..."
for i in $(seq 1 12); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "DHIS2 not ready (HTTP $HTTP_CODE), waiting 5s..."
    sleep 5
done

# 2. Record Task Start Time (Timestamp & ISO)
# DHIS2 uses ISO 8601 for created fields
date +%s > /tmp/task_start_timestamp
date -u +"%Y-%m-%dT%H:%M:%S.000Z" > /tmp/task_start_iso
TASK_START_ISO=$(cat /tmp/task_start_iso)
echo "Task start time (ISO): $TASK_START_ISO"

# 3. Clean up any previous attempts (Idempotency)
# We search for objects with specific names and delete them if they exist
echo "Cleaning up potential pre-existing objects..."

# Find Predictor
PREV_PRED_ID=$(dhis2_api "predictors?filter=name:ilike:Threshold&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['predictors'][0]['id']) if d.get('predictors') else print('')" 2>/dev/null)

if [ -n "$PREV_PRED_ID" ]; then
    echo "Deleting previous predictor: $PREV_PRED_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/predictors/$PREV_PRED_ID" >/dev/null
fi

# Find Data Element
PREV_DE_ID=$(dhis2_api "dataElements?filter=name:eq:Malaria+Cases+Expected+Threshold&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['dataElements'][0]['id']) if d.get('dataElements') else print('')" 2>/dev/null)

if [ -n "$PREV_DE_ID" ]; then
    echo "Deleting previous data element: $PREV_DE_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/dataElements/$PREV_DE_ID" >/dev/null
fi

# 4. Record Initial Counts (as baseline)
INITIAL_DE_COUNT=$(dhis2_api "dataElements?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; print(json.load(sys.stdin).get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_DE_COUNT" > /tmp/initial_de_count

INITIAL_PRED_COUNT=$(dhis2_api "predictors?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; print(json.load(sys.stdin).get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_PRED_COUNT" > /tmp/initial_pred_count

echo "Baseline counts - Data Elements: $INITIAL_DE_COUNT, Predictors: $INITIAL_PRED_COUNT"

# 5. Launch Firefox
echo "Launching Firefox..."
DHIS2_URL="http://localhost:8080/dhis-web-commons/security/login.action"

if pgrep -f firefox > /dev/null; then
    pkill -f firefox
    sleep 2
fi

su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "firefox\|mozilla\|DHIS"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Focus and Maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# 6. Take Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="