#!/bin/bash
echo "=== Setting up automatic_lookup_enrichment task ==="

source /workspace/scripts/task_utils.sh

# Record initial state: capture existing lookup definitions and saved searches
echo "Recording baseline state..."

# Initial Lookup Definitions
INITIAL_LOOKUPS=$(curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/data/transforms/lookups?output_mode=json&count=0" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(json.dumps([e.get('name') for e in data.get('entry', [])]))
except:
    print('[]')
" 2>/dev/null)
echo "$INITIAL_LOOKUPS" > /tmp/initial_lookups.json

# Initial Saved Searches
INITIAL_SEARCHES=$(curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches?output_mode=json&count=0" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(json.dumps([e.get('name') for e in data.get('entry', [])]))
except:
    print('[]')
" 2>/dev/null)
echo "$INITIAL_SEARCHES" > /tmp/initial_searches.json

echo "$(date +%s)" > /tmp/task_start_time.txt

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

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