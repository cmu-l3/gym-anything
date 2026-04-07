#!/bin/bash
echo "=== Exporting shared_credential_detection result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query REST API for all 3 artifacts
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

def run_splunk_query(endpoint):
    try:
        res = subprocess.run(
            ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
             f'https://localhost:8089{endpoint}?output_mode=json&count=0'],
            capture_output=True, text=True
        )
        return json.loads(res.stdout).get('entry', [])
    except Exception as e:
        return []

# 1. Fetch Event Types
event_types = [e.get('name', '') for e in run_splunk_query('/servicesNS/-/-/saved/eventtypes')]

# 2. Fetch Saved Searches
searches = {}
for e in run_splunk_query('/servicesNS/-/-/saved/searches'):
    searches[e.get('name', '')] = e.get('content', {})

# 3. Fetch Dashboards
dashboards = {}
for e in run_splunk_query('/servicesNS/-/-/data/ui/views'):
    dashboards[e.get('name', '')] = e.get('content', {}).get('eai:data', '')

output = {
    "event_types": event_types,
    "searches": searches,
    "dashboards": dashboards
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

safe_write_json "$TEMP_JSON" /tmp/shared_credential_detection_result.json
echo "Result saved to /tmp/shared_credential_detection_result.json"
cat /tmp/shared_credential_detection_result.json
echo "=== Export complete ==="