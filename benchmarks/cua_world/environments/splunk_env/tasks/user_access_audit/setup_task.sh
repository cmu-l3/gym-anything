#!/bin/bash
echo "=== Setting up user_access_audit task ==="

source /workspace/scripts/task_utils.sh

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Record baseline saved searches
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
echo "$INITIAL_SS" > /tmp/audit_initial_saved_searches.json

# Record baseline lookup files
echo "Recording baseline lookup files..."
INITIAL_LOOKUPS=$(curl -sk -u admin:SplunkAdmin1! \
    "https://localhost:8089/servicesNS/-/-/data/lookup-table-files?output_mode=json&count=0" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    entries = data.get('entry', [])
    names = [e.get('name', '') for e in entries]
    print(json.dumps(names))
except:
    print('[]')
" 2>/dev/null)
echo "$INITIAL_LOOKUPS" > /tmp/audit_initial_lookups.json

# Record baseline lookup definitions
echo "Recording baseline lookup definitions..."
INITIAL_LOOKUP_DEFS=$(curl -sk -u admin:SplunkAdmin1! \
    "https://localhost:8089/servicesNS/-/-/data/transforms/lookups?output_mode=json&count=0" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    entries = data.get('entry', [])
    names = [e.get('name', '') for e in entries]
    print(json.dumps(names))
except:
    print('[]')
" 2>/dev/null)
echo "$INITIAL_LOOKUP_DEFS" > /tmp/audit_initial_lookup_defs.json

INITIAL_SS_COUNT=$(echo "$INITIAL_SS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
echo "Baseline: $INITIAL_SS_COUNT saved searches"

echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure Firefox is running with Splunk visible
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    exit 1
fi

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete. Baseline: $INITIAL_SS_COUNT saved searches ==="
