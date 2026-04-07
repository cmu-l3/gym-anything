#!/bin/bash
echo "=== Setting up session_hijacking_detection task ==="

source /workspace/scripts/task_utils.sh

# Record initial saved searches (baseline)
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
echo "$INITIAL_SS" > /tmp/session_hijack_initial_searches.json

INITIAL_COUNT=$(echo "$INITIAL_SS" | python3 -c "
import sys, json
try:
    print(len(json.load(sys.stdin)))
except:
    print(0)
" 2>/dev/null)
echo "$INITIAL_COUNT" > /tmp/initial_saved_search_count

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Ensure Firefox is running with Splunk visible BEFORE task starts
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3
# Take initial screenshot AFTER successful verification
take_screenshot /tmp/task_start_screenshot.png
echo "Task start screenshot taken"

echo "$(date +%s)" > /tmp/task_start_timestamp
echo "=== Task setup complete. Baseline: $INITIAL_COUNT saved searches ==="