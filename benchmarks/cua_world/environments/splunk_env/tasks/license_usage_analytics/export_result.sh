#!/bin/bash
echo "=== Exporting license_usage_analytics result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for visual evidence
take_screenshot /tmp/task_end_screenshot.png

# Query the Splunk REST API to safely export the defined objects for the verifier
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess, re

# Load baselines
try:
    with open('/tmp/license_initial_ss.json') as f:
        initial_ss = json.load(f)
except:
    initial_ss = []

try:
    with open('/tmp/license_initial_dash.json') as f:
        initial_dash = json.load(f)
except:
    initial_dash = []

# Fetch all saved searches
ss_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

all_searches = []
try:
    ss_data = json.loads(ss_result.stdout)
    for entry in ss_data.get('entry', []):
        name = entry.get('name', '')
        search_query = entry.get('content', {}).get('search', '')
        all_searches.append({
            "name": name,
            "search": search_query,
            "is_new": name not in initial_ss
        })
except:
    pass

# Fetch all dashboards
dash_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/data/ui/views?output_mode=json&count=0'],
    capture_output=True, text=True
)

all_dashboards = []
try:
    dash_data = json.loads(dash_result.stdout)
    for entry in dash_data.get('entry', []):
        name = entry.get('name', '')
        xml = entry.get('content', {}).get('eai:data', '')
        # Count explicit panel tags in the dashboard XML
        panel_count = len(re.findall(r'<panel\b', xml, re.IGNORECASE)) if xml else 0
        all_dashboards.append({
            "name": name,
            "xml": xml,
            "panel_count": panel_count,
            "is_new": name not in initial_dash
        })
except:
    pass

output = {
    "searches": all_searches,
    "dashboards": all_dashboards
}
print(json.dumps(output))
PYEOF
)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/license_usage_result.json
echo "Result saved to /tmp/license_usage_result.json"
echo "=== Export complete ==="