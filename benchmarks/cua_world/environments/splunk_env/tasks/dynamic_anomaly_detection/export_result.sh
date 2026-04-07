#!/bin/bash
echo "=== Exporting dynamic_anomaly_detection result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Analyze saved searches to find the new statistical alert
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

def normalize_name(name):
    return name.lower().replace(' ', '_').replace('-', '_')

try:
    with open('/tmp/anomaly_initial_saved_searches.json') as f:
        initial_names = json.load(f)
except:
    initial_names = []

result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

new_searches = []
found_target_alert = False
target_alert_data = {}

expected_name_normalized = "statistical_web_error_spike"

try:
    data = json.loads(result.stdout)
    for entry in data.get('entry', []):
        name = entry.get('name', '')
        if name not in initial_names:
            content = entry.get('content', {})
            search_data = {
                "name": name,
                "search": content.get('search', ''),
                "is_scheduled": content.get('is_scheduled', '0') == '1',
                "cron_schedule": content.get('cron_schedule', ''),
            }
            new_searches.append(search_data)
            
            # Check if this is the specific alert requested
            if normalize_name(name) == expected_name_normalized:
                found_target_alert = True
                target_alert_data = search_data
                
except Exception as e:
    pass

output = {
    "new_searches": new_searches,
    "found_target_alert": found_target_alert,
    "target_alert_data": target_alert_data,
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

safe_write_json "$TEMP_JSON" /tmp/dynamic_anomaly_detection_result.json
echo "Result saved to /tmp/dynamic_anomaly_detection_result.json"
cat /tmp/dynamic_anomaly_detection_result.json
echo "=== Export complete ==="