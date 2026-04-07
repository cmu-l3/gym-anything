#!/bin/bash
echo "=== Setting up data_exfiltration_monitor task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Record baseline saved searches and dashboards
echo "Recording baseline configuration..."
splunk_list_saved_searches | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(json.dumps([e.get('name', '') for e in data.get('entry', [])]))
except:
    print('[]')
" > /tmp/initial_saved_searches.json 2>/dev/null

splunk_list_dashboards | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(json.dumps([e.get('name', '') for e in data.get('entry', [])]))
except:
    print('[]')
" > /tmp/initial_dashboards.json 2>/dev/null

# Ensure Firefox is running with Splunk visible
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3
take_screenshot /tmp/task_initial.png
echo "=== Setup complete ==="