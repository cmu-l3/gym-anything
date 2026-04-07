#!/bin/bash
echo "=== Setting up security_investigation_workbook task ==="

source /workspace/scripts/task_utils.sh

# Record initial dashboards to detect new ones
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

INITIAL_COUNT=$(echo "$INITIAL_DASHBOARDS" | python3 -c "
import sys, json
try:
    print(len(json.load(sys.stdin)))
except:
    print(0)
" 2>/dev/null)

echo "$INITIAL_COUNT" > /tmp/initial_dashboard_count
echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# CRITICAL: Ensure Firefox is running with Splunk visible BEFORE task starts
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    echo "Task setup FAILED - task start state is INVALID"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png
echo "Task start screenshot taken"

echo "=== Task setup complete. Baseline: $INITIAL_COUNT dashboards ==="