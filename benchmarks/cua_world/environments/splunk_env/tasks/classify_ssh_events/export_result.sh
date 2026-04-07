#!/bin/bash
echo "=== Exporting classify_ssh_events result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve current state from Splunk REST API
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

def get_splunk_data(endpoint):
    try:
        res = subprocess.run(
            ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', f'https://localhost:8089{endpoint}?output_mode=json&count=0'],
            capture_output=True, text=True
        )
        return json.loads(res.stdout).get('entry', [])
    except Exception as e:
        return []

try:
    with open('/tmp/classify_ssh_initial.json', 'r') as f:
        initial_state = json.load(f)
except Exception:
    initial_state = {"eventtypes": [], "searches": []}

eventtypes = get_splunk_data('/servicesNS/-/-/saved/eventtypes')
tags = get_splunk_data('/servicesNS/-/-/configs/conf-tags')
searches = get_splunk_data('/servicesNS/-/-/saved/searches')

output = {
    "initial_state": initial_state,
    "eventtypes": [{"name": e.get('name', ''), "search": e.get('content', {}).get('search', '')} for e in eventtypes],
    "tags": [{"name": t.get('name', ''), "content": t.get('content', {})} for t in tags],
    "searches": [{"name": s.get('name', ''), "search": s.get('content', {}).get('search', '')} for s in searches]
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

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="