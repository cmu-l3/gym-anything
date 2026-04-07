#!/bin/bash
echo "=== Exporting temporal_access_anomaly_detection result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Use Python to extract all current dashboards and saved searches, then diff with baseline
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

# Load baselines
try:
    with open('/tmp/baseline_dashboards.json', 'r') as f:
        baseline_dashboards = json.load(f)
except:
    baseline_dashboards = []

try:
    with open('/tmp/baseline_searches.json', 'r') as f:
        baseline_searches = json.load(f)
except:
    baseline_searches = []

# Fetch current dashboards
dash_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/data/ui/views?output_mode=json&count=0'],
    capture_output=True, text=True
)

new_dashboards = []
try:
    dash_data = json.loads(dash_result.stdout)
    for entry in dash_data.get('entry', []):
        name = entry.get('name', '')
        if name not in baseline_dashboards:
            xml = entry.get('content', {}).get('eai:data', '')
            new_dashboards.append({
                "name": name,
                "xml_data": xml
            })
except Exception as e:
    pass

# Fetch current saved searches
ss_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

new_searches = []
try:
    ss_data = json.loads(ss_result.stdout)
    for entry in ss_data.get('entry', []):
        name = entry.get('name', '')
        if name not in baseline_searches:
            content = entry.get('content', {})
            new_searches.append({
                "name": name,
                "search": content.get('search', ''),
                "is_scheduled": content.get('is_scheduled', '0') == '1',
                "cron_schedule": content.get('cron_schedule', ''),
                "alert_type": content.get('alert_type', '')
            })
except Exception as e:
    pass

output = {
    "new_dashboards": new_dashboards,
    "new_searches": new_searches
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

safe_write_json "$TEMP_JSON" /tmp/temporal_access_result.json
echo "Result saved to /tmp/temporal_access_result.json"
cat /tmp/temporal_access_result.json
echo "=== Export complete ==="