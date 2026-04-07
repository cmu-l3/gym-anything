#!/bin/bash
echo "=== Setting up dashboard_drilldown_routing task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Record initial dashboards to ensure agent creates new ones
echo "Recording baseline dashboards..."
INITIAL_DASHBOARDS=$(splunk_list_dashboards | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    entries = data.get('entry', [])
    names = [e.get('name', '') for e in entries]
    print(json.dumps(names))
except:
    print('[]')
" 2>/dev/null)
echo "$INITIAL_DASHBOARDS" > /tmp/initial_dashboards.json
echo "Baseline recorded."

# Ensure Firefox is running with Splunk visible
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete ==="