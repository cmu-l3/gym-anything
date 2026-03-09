#!/bin/bash
echo "=== Exporting soc_lateral_movement result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

try:
    with open('/tmp/soc_lm_initial_saved_searches.json') as f:
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
                "alert_type": content.get('alert_type', ''),
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

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/soc_lateral_movement_result.json
echo "Result saved to /tmp/soc_lateral_movement_result.json"
cat /tmp/soc_lateral_movement_result.json
echo "=== Export complete ==="
