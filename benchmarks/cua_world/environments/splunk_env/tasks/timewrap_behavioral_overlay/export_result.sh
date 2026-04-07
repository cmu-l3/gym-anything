#!/bin/bash
echo "=== Exporting timewrap_behavioral_overlay result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Fetch current saved searches
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches?output_mode=json&count=0" \
    > /tmp/current_saved_searches.json 2>/dev/null

# Fetch current dashboards
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/data/ui/views?output_mode=json&count=0" \
    > /tmp/current_dashboards.json 2>/dev/null

# Analyze the results using Python
ANALYSIS=$(python3 - << 'PYEOF'
import sys
import json
import re

def normalize_name(name):
    return name.lower().replace(' ', '_').replace('-', '_')

# Load the current state
try:
    with open('/tmp/current_saved_searches.json', 'r') as f:
        searches_data = json.load(f)
        all_searches = searches_data.get('entry', [])
except Exception:
    all_searches = []

try:
    with open('/tmp/current_dashboards.json', 'r') as f:
        dashboards_data = json.load(f)
        all_dashboards = dashboards_data.get('entry', [])
except Exception:
    all_dashboards = []

expected_report_norm = "dod_failed_auth_overlay"
expected_dashboard_norm = "authentication_baselines"

report_found = False
report_search_query = ""
report_name_actual = ""

dash_found = False
dash_xml = ""
dash_name_actual = ""

# Search for the expected report
for entry in all_searches:
    name = entry.get('name', '')
    if normalize_name(name) == expected_report_norm:
        report_found = True
        report_name_actual = name
        report_search_query = entry.get('content', {}).get('search', '')
        break

# Search for the expected dashboard
for entry in all_dashboards:
    name = entry.get('name', '')
    if normalize_name(name) == expected_dashboard_norm:
        dash_found = True
        dash_name_actual = name
        dash_xml = entry.get('content', {}).get('eai:data', '')
        break

output = {
    "report_found": report_found,
    "report_name": report_name_actual,
    "report_search_query": report_search_query,
    "dashboard_found": dash_found,
    "dashboard_name": dash_name_actual,
    "dashboard_xml": dash_xml
}

print(json.dumps(output))
PYEOF
)

# Read task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "analysis": $ANALYSIS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="