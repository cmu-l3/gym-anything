#!/bin/bash
echo "=== Setting up automated_ip_blocklist_population task ==="

source /workspace/scripts/task_utils.sh

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Clean up any pre-existing blocklist file to ensure a clean state
echo "Cleaning up any existing blocklist files..."
rm -f /opt/splunk/etc/apps/search/lookups/auto_blocklist.csv 2>/dev/null || true
rm -f /opt/splunk/etc/users/admin/search/lookups/auto_blocklist.csv 2>/dev/null || true

# Record baseline saved searches (to accurately detect the new ones added by agent)
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

# Record timestamp for anti-gaming verification
echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure Firefox is running with Splunk visible (CRITICAL)
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    exit 1
fi

# Additional wait to ensure UI is fully interactive
sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup complete ==="