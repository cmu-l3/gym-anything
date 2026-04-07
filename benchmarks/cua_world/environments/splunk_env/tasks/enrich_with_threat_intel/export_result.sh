#!/bin/bash
echo "=== Exporting enrich_with_threat_intel result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Extract newly created artifacts using Python
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

def get_api_data(endpoint):
    cmd = ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', f'https://localhost:8089{endpoint}?output_mode=json&count=0']
    res = subprocess.run(cmd, capture_output=True, text=True)
    try:
        return json.loads(res.stdout).get('entry', [])
    except:
        return []

# Load baselines
try:
    with open('/tmp/baseline_lookups.json') as f: base_lookups = set(json.load(f))
except: base_lookups = set()

try:
    with open('/tmp/baseline_defs.json') as f: base_defs = set(json.load(f))
except: base_defs = set()

try:
    with open('/tmp/baseline_searches.json') as f: base_searches = set(json.load(f))
except: base_searches = set()

# Get current data
curr_lookups = get_api_data('/servicesNS/-/-/data/lookup-table-files')
curr_defs = get_api_data('/servicesNS/-/-/data/transforms/lookups')
curr_searches = get_api_data('/servicesNS/-/-/saved/searches')

# Diff
new_lookups = [e.get('name', '') for e in curr_lookups if e.get('name', '') not in base_lookups]
new_defs = [e.get('name', '') for e in curr_defs if e.get('name', '') not in base_defs]

new_searches_detailed = []
for e in curr_searches:
    name = e.get('name', '')
    if name not in base_searches:
        new_searches_detailed.append({
            "name": name,
            "search": e.get('content', {}).get('search', '')
        })

output = {
    "new_lookups": new_lookups,
    "new_defs": new_defs,
    "new_searches": new_searches_detailed
}
print(json.dumps(output))
PYEOF
)

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
TASK_DURATION=$((TASK_END - TASK_START))

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "task_duration_seconds": ${TASK_DURATION},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/threat_intel_result.json
echo "Result saved to /tmp/threat_intel_result.json"
cat /tmp/threat_intel_result.json
echo "=== Export complete ==="