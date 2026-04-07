#!/bin/bash
# Setup script for District Immunization Completion Analysis task

echo "=== Setting up District Immunization Completion Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Inline fallbacks
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
        DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
    }
fi

# ---------------------------------------------------------------
# Verify DHIS2 is running
# ---------------------------------------------------------------
echo "Checking DHIS2 health..."
for i in $(seq 1 12); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "Waiting 10s... (attempt $i/12)"
    sleep 10
done

# ---------------------------------------------------------------
# Clean up pre-existing items BEFORE recording timestamp
# ---------------------------------------------------------------
echo "Cleaning up pre-existing items..."

# Delete any existing indicator matching our target name
EXISTING_IND=$(dhis2_api "indicators?filter=name:ilike:Full+Immunization+Dropout&fields=id&paging=false" 2>/dev/null | \
    python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for ind in data.get('indicators', []):
        print(ind['id'])
except:
    pass
" 2>/dev/null)

for IND_ID in $EXISTING_IND; do
    echo "Deleting pre-existing indicator: $IND_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/indicators/$IND_ID" > /dev/null 2>&1
done

# Delete any existing visualization matching our target name
EXISTING_VIZ=$(dhis2_api "visualizations?filter=name:ilike:Bo+Facility+Immunization&fields=id&paging=false" 2>/dev/null | \
    python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for v in data.get('visualizations', []):
        print(v['id'])
except:
    pass
" 2>/dev/null)

for VIZ_ID in $EXISTING_VIZ; do
    echo "Deleting pre-existing visualization: $VIZ_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/visualizations/$VIZ_ID" > /dev/null 2>&1
done

# Clean target files
rm -f /home/ga/Desktop/dropout_report.txt 2>/dev/null || true

# Clean Downloads of CSV/XLSX files
rm -f /home/ga/Downloads/*.csv /home/ga/Downloads/*.xls* /home/ga/Downloads/*.tsv 2>/dev/null || true

# ---------------------------------------------------------------
# Record task start time (AFTER cleanup)
# ---------------------------------------------------------------
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# ---------------------------------------------------------------
# Record initial IDs for new-item detection
# ---------------------------------------------------------------
echo "Recording baseline state..."

# Initial indicator IDs
dhis2_api "indicators?fields=id&paging=false" 2>/dev/null | \
    python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for ind in data.get('indicators', []):
        print(ind['id'])
except:
    pass
" 2>/dev/null > /tmp/initial_indicator_ids

# Initial visualization IDs
dhis2_api "visualizations?fields=id&paging=false" 2>/dev/null | \
    python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for v in data.get('visualizations', []):
        print(v['id'])
except:
    pass
" 2>/dev/null > /tmp/initial_viz_ids

INITIAL_IND_COUNT=$(wc -l < /tmp/initial_indicator_ids 2>/dev/null || echo "0")
INITIAL_VIZ_COUNT=$(wc -l < /tmp/initial_viz_ids 2>/dev/null || echo "0")

echo "Initial indicators: $INITIAL_IND_COUNT"
echo "Initial visualizations: $INITIAL_VIZ_COUNT"

# ---------------------------------------------------------------
# Verify required data elements exist
# ---------------------------------------------------------------
echo "Verifying required data elements..."

DE_CHECK=$(curl -s -u admin:district "http://localhost:8080/api/dataElements?filter=name:ilike:penta&fields=id,name&paging=false" 2>/dev/null | \
python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    penta1 = None
    for de in data.get('dataElements', []):
        name = de.get('name', '')
        if 'penta' in name.lower() and '1' in name:
            penta1 = de['id']
            break
    print(penta1 or '')
except:
    print('')
" 2>/dev/null)

if [ -z "$DE_CHECK" ]; then
    echo "WARNING: Could not find Penta 1 data element"
else
    echo "Found Penta 1 data element: $DE_CHECK"
fi

FULLY_IMM_CHECK=$(curl -s -u admin:district "http://localhost:8080/api/dataElements?filter=name:ilike:fully+immunized&fields=id,name&paging=false" 2>/dev/null | \
python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for de in data.get('dataElements', []):
        print(de['id'])
        break
except:
    print('')
" 2>/dev/null)

if [ -z "$FULLY_IMM_CHECK" ]; then
    echo "WARNING: Could not find Fully immunized data element"
else
    echo "Found Fully immunized data element: $FULLY_IMM_CHECK"
fi

# ---------------------------------------------------------------
# Ensure directories exist
# ---------------------------------------------------------------
mkdir -p /home/ga/Downloads
mkdir -p /home/ga/Desktop

# ---------------------------------------------------------------
# Ensure Firefox is running and focused
# ---------------------------------------------------------------
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

# Wait for Firefox window
for i in $(seq 1 10); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|DHIS"; then
        break
    fi
    sleep 2
done

# Focus and maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Task Start: $TASK_START"
echo "Initial Indicators: $INITIAL_IND_COUNT"
echo "Initial Visualizations: $INITIAL_VIZ_COUNT"
echo "Penta 1 DE: $DE_CHECK"
echo "Fully Immunized DE: $FULLY_IMM_CHECK"
