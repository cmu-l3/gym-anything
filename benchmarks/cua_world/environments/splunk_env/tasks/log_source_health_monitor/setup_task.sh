#!/bin/bash
echo "=== Setting up log_source_health_monitor task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
echo "$(date +%s)" > /tmp/task_start_time.txt

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Record baseline saved searches to detect new ones
echo "Recording baseline saved searches..."
INITIAL_SS=$(splunk_list_saved_searches | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    entries = data.get('entry', [])
    names = [e.get('name', '') for e in entries]
    print(json.dumps(names))
except:
    print('[]')
" 2>/dev/null)
echo "$INITIAL_SS" > /tmp/initial_saved_searches.json

INITIAL_COUNT=$(echo "$INITIAL_SS" | python3 -c "
import sys, json
try:
    print(len(json.load(sys.stdin)))
except:
    print(0)
" 2>/dev/null)
echo "Baseline: $INITIAL_COUNT saved searches"

# CRITICAL: Ensure Firefox is running with Splunk visible BEFORE task starts
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete. Baseline: $INITIAL_COUNT saved searches ==="