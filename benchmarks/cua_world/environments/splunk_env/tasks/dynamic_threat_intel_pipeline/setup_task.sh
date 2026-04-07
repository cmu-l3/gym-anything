#!/bin/bash
echo "=== Setting up dynamic_threat_intel_pipeline task ==="

source /workspace/scripts/task_utils.sh

# Start/Check Splunk
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Clean up any previous lookups if they exist (to ensure a clean state)
rm -f /opt/splunk/etc/apps/search/lookups/local_threat_intel.csv 2>/dev/null || true
rm -f /opt/splunk/etc/system/local/lookups/local_threat_intel.csv 2>/dev/null || true

# Record initial saved searches to detect the new ones
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
echo "Initial saved searches count: $INITIAL_COUNT"

# Timestamp
date +%s > /tmp/task_start_time.txt

# Ensure Firefox is ready
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Task setup complete ==="