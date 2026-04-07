#!/bin/bash
echo "=== Setting up web_scraper_bot_detection task ==="

source /workspace/scripts/task_utils.sh

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Record baseline saved searches and dashboards to detect newly created ones
echo "Recording baseline state..."

INITIAL_SS=$(splunk_list_saved_searches | python3 -c "
import sys, json
try:
    print(json.dumps([e.get('name', '') for e in json.load(sys.stdin).get('entry', [])]))
except:
    print('[]')
" 2>/dev/null)
echo "$INITIAL_SS" > /tmp/baseline_saved_searches.json

INITIAL_DASH=$(splunk_list_dashboards | python3 -c "
import sys, json
try:
    print(json.dumps([e.get('name', '') for e in json.load(sys.stdin).get('entry', [])]))
except:
    print('[]')
" 2>/dev/null)
echo "$INITIAL_DASH" > /tmp/baseline_dashboards.json

echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure Firefox is running with Splunk visible
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete ==="