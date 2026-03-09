#!/bin/bash
echo "=== Setting up create_alert task ==="

source /workspace/scripts/task_utils.sh

# Record initial saved searches (to detect new ones)
echo "Recording initial state..."

INITIAL_SAVED_SEARCHES=$(splunk_list_saved_searches | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    entries = data.get('entry', [])
    names = [e.get('name', '') for e in entries]
    print(json.dumps(names))
except:
    print('[]')
" 2>/dev/null)
echo "$INITIAL_SAVED_SEARCHES" > /tmp/initial_saved_searches.json

INITIAL_COUNT=$(echo "$INITIAL_SAVED_SEARCHES" | python3 -c "
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

# CRITICAL: Ensure Firefox is running with Splunk visible BEFORE task starts
# Using 120 second timeout as recommended by audit
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    echo "Task setup FAILED - task start state is INVALID"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    # EXIT WITH ERROR - Do not continue with invalid state
    exit 1
fi

# Additional wait to ensure UI is fully loaded
sleep 3

# Take initial screenshot AFTER successful verification
take_screenshot /tmp/task_start_screenshot.png
echo "Task start screenshot taken"

echo "=== Task setup complete ==="
echo "Initial saved search count: $INITIAL_COUNT"
