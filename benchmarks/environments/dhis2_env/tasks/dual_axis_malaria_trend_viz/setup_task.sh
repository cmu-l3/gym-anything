#!/bin/bash
# Setup script for Dual Axis Malaria Trend Visualization task

echo "=== Setting up Dual Axis Malaria Trend Viz Task ==="

source /workspace/scripts/task_utils.sh

# Fallback API function if not in utils
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
fi

# 1. Verify DHIS2 Health
echo "Checking DHIS2 health..."
for i in $(seq 1 6); do
    if curl -s "http://localhost:8080/api/system/info" | grep -q "version"; then
        echo "DHIS2 is ready."
        break
    fi
    echo "Waiting for DHIS2..."
    sleep 5
done

# 2. Clean up previous artifacts (Anti-Gaming / Clean Slate)
echo "Cleaning up previous task artifacts..."

# Remove the output file
rm -f /home/ga/Desktop/malaria_chart.png

# Remove the specific visualization if it exists (by name)
# We search for it, then delete by ID
EXISTING_ID=$(dhis2_api "visualizations?filter=displayName:eq:Bo+Malaria+Testing+vs+Positivity+2024&fields=id" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['visualizations'][0]['id']) if d.get('visualizations') else print('')" 2>/dev/null)

if [ -n "$EXISTING_ID" ]; then
    echo "Removing pre-existing visualization: $EXISTING_ID"
    curl -s -u admin:district -X DELETE "http://localhost:8080/api/visualizations/$EXISTING_ID" > /dev/null
fi

# 3. Record Start Time
date +%s > /tmp/task_start_timestamp
echo "Task start time recorded."

# 4. Prepare Browser
echo "Launching Firefox..."
DHIS2_URL="http://localhost:8080/dhis-web-commons/security/login.action"
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &"
    sleep 8
fi

# Focus window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="