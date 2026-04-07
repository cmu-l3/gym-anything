#!/bin/bash
echo "=== Setting up log_source_coverage_audit task ==="

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

# Clean up any pre-existing artifacts that might match the task goal to ensure clean state
echo "Cleaning up any pre-existing task artifacts..."
curl -sk -u "admin:SplunkAdmin1!" -X DELETE "https://localhost:8089/servicesNS/admin/search/saved/searches/Audit_Log_Coverage_Gaps" >/dev/null 2>&1 || true
curl -sk -u "admin:SplunkAdmin1!" -X DELETE "https://localhost:8089/servicesNS/admin/search/data/ui/views/Compliance_Audit_Dashboard" >/dev/null 2>&1 || true
# Remove the lookup file if it exists physically
find /opt/splunk/etc -name "non_compliant_hosts.csv" -type f -delete 2>/dev/null || true

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

# Record baseline dashboards
echo "Recording baseline dashboards..."
INITIAL_DASHBOARDS=$(splunk_list_dashboards | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    entries = data.get('entry', [])
    names = [e.get('name', '') for e in entries]
    print(json.dumps(names))
except:
    print('[]')
" 2>/dev/null)
echo "$INITIAL_DASHBOARDS" > /tmp/audit_initial_dashboards.json

# CRITICAL: Ensure Firefox is running with Splunk visible BEFORE task starts
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

sleep 3
take_screenshot /tmp/task_initial_state.png
echo "=== Setup complete ==="