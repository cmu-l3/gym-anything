#!/bin/bash
echo "=== Setting up ecommerce_conversion_analytics task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Check if tutorial data is loaded
TUTORIAL_EVENTS=$(splunk_count_events "tutorial")
echo "Tutorial events found: $TUTORIAL_EVENTS"

# Record baseline saved searches and dashboards
echo "Recording baseline artifacts..."
splunk_list_saved_searches | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(json.dumps([e.get('name', '') for e in data.get('entry', [])]))
except:
    print('[]')
" > /tmp/baseline_searches.json 2>/dev/null

splunk_list_dashboards | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(json.dumps([e.get('name', '') for e in data.get('entry', [])]))
except:
    print('[]')
" > /tmp/baseline_dashboards.json 2>/dev/null

# CRITICAL: Ensure Firefox is running with Splunk visible BEFORE task starts
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete ==="