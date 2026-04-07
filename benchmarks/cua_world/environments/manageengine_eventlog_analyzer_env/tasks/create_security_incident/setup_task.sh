#!/bin/bash
# Setup for "create_security_incident" task
echo "=== Setting up Create Security Incident task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer

# Record initial incident count (via API)
# We assume the API returns a list or count. If not, we default to 0.
echo "Recording initial incident count..."
INITIAL_INCIDENTS=$(ela_api_call "/event/api/v2/incidents" "GET" 2>/dev/null)
# Extract count using python one-liner (handles potential JSON errors gracefully)
INITIAL_COUNT=$(echo "$INITIAL_INCIDENTS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Adjust key based on actual API response structure (often 'incidents' or 'data')
    incidents = data.get('incidents', data.get('data', []))
    print(len(incidents))
except:
    print('0')
")
echo "$INITIAL_COUNT" > /tmp/initial_incident_count.txt
echo "Initial incident count: $INITIAL_COUNT"

# Ensure Firefox is open and on the Dashboard
# We start at the dashboard to force the agent to navigate to Incidents
ensure_firefox_on_ela "/event/index.do"
sleep 5

# Maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | awk '{print $1}' | head -n 1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -ia "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="