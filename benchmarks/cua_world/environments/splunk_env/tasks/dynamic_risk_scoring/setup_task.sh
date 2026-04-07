#!/bin/bash
echo "=== Setting up dynamic_risk_scoring task ==="

source /workspace/scripts/task_utils.sh

# Record initial saved searches (to detect new ones added by agent)
echo "Recording baseline saved searches..."
INITIAL_SS=$(curl -sk -u "admin:SplunkAdmin1!" "https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    entries = data.get('entry', [])
    names = [e.get('name', '') for e in entries]
    print(json.dumps(names))
except:
    print('[]')
")
echo "$INITIAL_SS" > /tmp/initial_saved_searches.json

INITIAL_COUNT=$(echo "$INITIAL_SS" | python3 -c "
import sys, json
try:
    print(len(json.load(sys.stdin)))
except:
    print(0)
")
echo "Baseline: $INITIAL_COUNT saved searches"

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
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "$(date +%s)" > /tmp/task_start_timestamp

echo "=== Setup complete ==="