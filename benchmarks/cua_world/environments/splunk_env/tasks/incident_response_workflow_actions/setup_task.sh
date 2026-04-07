#!/bin/bash
echo "=== Setting up incident_response_workflow_actions task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Splunk is running
if splunk_is_running; then
    echo "Splunk is running"
else
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Record baseline state for Workflow Actions
echo "Recording baseline workflow actions..."
INITIAL_WA=$(curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/data/ui/workflow-actions?output_mode=json&count=0" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    names = [e.get('name', '') for e in data.get('entry', [])]
    print(json.dumps(names))
except Exception as e:
    print('[]')
" 2>/dev/null)
echo "$INITIAL_WA" > /tmp/initial_workflow_actions.json

# Record baseline state for Saved Searches
echo "Recording baseline saved searches..."
INITIAL_SS=$(splunk_list_saved_searches | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    names = [e.get('name', '') for e in data.get('entry', [])]
    print(json.dumps(names))
except:
    print('[]')
" 2>/dev/null)
echo "$INITIAL_SS" > /tmp/initial_saved_searches.json

INITIAL_WA_COUNT=$(echo "$INITIAL_WA" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(echo "$INITIAL_SS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

echo "Baseline recorded: $INITIAL_WA_COUNT workflow actions, $INITIAL_SS_COUNT saved searches"

# CRITICAL: Ensure Firefox is running with Splunk visible BEFORE task starts
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

echo "=== Task setup complete ==="