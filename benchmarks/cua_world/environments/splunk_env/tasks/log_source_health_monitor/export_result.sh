#!/bin/bash
echo "=== Exporting log_source_health_monitor result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Fetch current saved searches via REST API and process them in Python
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

try:
    with open('/tmp/initial_saved_searches.json') as f:
        initial_names = json.load(f)
except:
    initial_names = []

result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

new_searches = []
try:
    data = json.loads(result.stdout)
    for entry in data.get('entry', []):
        name = entry.get('name', '')
        if name not in initial_names:
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
    "new_searches": new_searches,
    "initial_count": len(initial_names),
    "new_count": len(new_searches)
}
print(json.dumps(output))
PYEOF
)

# Create the final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)",
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="