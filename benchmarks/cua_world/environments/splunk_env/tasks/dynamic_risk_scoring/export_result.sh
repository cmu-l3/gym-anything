#!/bin/bash
echo "=== Exporting dynamic_risk_scoring result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Fetch all current saved searches via REST API
SEARCHES_TEMP=$(mktemp /tmp/searches.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" "https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0" > "$SEARCHES_TEMP" 2>/dev/null

# Parse and compare with initial state
ANALYSIS_TEMP=$(mktemp /tmp/analysis.XXXXXX.json)
python3 - "$SEARCHES_TEMP" > "$ANALYSIS_TEMP" << 'PYEOF'
import json
import sys

try:
    with open('/tmp/initial_saved_searches.json', 'r') as f:
        initial_ss = json.load(f)
except:
    initial_ss = []

try:
    with open(sys.argv[1], 'r') as f:
        current_data = json.load(f)
    entries = current_data.get('entry', [])
except:
    entries = []

new_searches = []
all_searches = []

for entry in entries:
    name = entry.get('name', '')
    content = entry.get('content', {})
    
    search_obj = {
        'name': name,
        'search': content.get('search', ''),
        'is_scheduled': content.get('is_scheduled', 0),
        'cron_schedule': content.get('cron_schedule', ''),
        'alert_type': content.get('alert_type', '')
    }
    
    all_searches.append(search_obj)
    
    if name not in initial_ss:
        new_searches.append(search_obj)

output = {
    'initial_count': len(initial_ss),
    'new_searches': new_searches,
    'all_searches': all_searches
}

print(json.dumps(output))
PYEOF

rm -f "$SEARCHES_TEMP"

# Create final result JSON
RESULT_TEMP=$(mktemp /tmp/result.XXXXXX.json)
cat > "$RESULT_TEMP" << EOF
{
    "analysis": $(cat "$ANALYSIS_TEMP"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

rm -f "$ANALYSIS_TEMP"

safe_write_json "$RESULT_TEMP" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="