#!/bin/bash
echo "=== Exporting incident_response_workflow_actions result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Extract all relevant data via Python script
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

try:
    with open('/tmp/initial_workflow_actions.json') as f:
        initial_wa = json.load(f)
except:
    initial_wa = []

try:
    with open('/tmp/initial_saved_searches.json') as f:
        initial_ss = json.load(f)
except:
    initial_ss = []

# Fetch current Workflow Actions
wa_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/data/ui/workflow-actions?output_mode=json&count=0'],
    capture_output=True, text=True
)

current_wa = []
try:
    wa_data = json.loads(wa_result.stdout)
    for entry in wa_data.get('entry', []):
        name = entry.get('name', '')
        content = entry.get('content', {})
        current_wa.append({
            "name": name,
            "is_new": name not in initial_wa,
            "type": content.get('type', ''),
            "link_uri": content.get('link.uri', ''),
            "search_string": content.get('search.search_string', ''),
            "label": content.get('label', '')
        })
except Exception as e:
    pass

# Fetch current Saved Searches
ss_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

current_ss = []
try:
    ss_data = json.loads(ss_result.stdout)
    for entry in ss_data.get('entry', []):
        name = entry.get('name', '')
        content = entry.get('content', {})
        current_ss.append({
            "name": name,
            "is_new": name not in initial_ss,
            "search": content.get('search', '')
        })
except Exception as e:
    pass

output = {
    "workflow_actions": current_wa,
    "saved_searches": current_ss,
    "initial_wa_count": len(initial_wa),
    "initial_ss_count": len(initial_ss)
}
print(json.dumps(output))
PYEOF
)

# Get task start time for verification
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/task_result.json
echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="