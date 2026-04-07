#!/bin/bash
echo "=== Exporting soc_alert_throttling_tuning result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Extract alert configuration from Splunk REST API
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

try:
    with open('/tmp/soc_alert_initial_saved_searches.json') as f:
        initial_ss = json.load(f)
except:
    initial_ss = []

# Query Splunk for all saved searches
result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

alert_data = {
    "found": False,
    "was_preexisting": False
}

try:
    data = json.loads(result.stdout)
    for entry in data.get('entry', []):
        name = entry.get('name', '')
        # Check for the specific alert name (case insensitive)
        if name.lower() == 'web_error_spike':
            content = entry.get('content', {})
            alert_data = {
                "found": True,
                "name": name,
                "was_preexisting": name in initial_ss,
                "search": content.get('search', ''),
                "is_scheduled": content.get('is_scheduled', 0),
                "cron_schedule": content.get('cron_schedule', ''),
                "suppress": content.get('alert.suppress', 0),
                "suppress_period": content.get('alert.suppress.period', ''),
                "suppress_fields": content.get('alert.suppress.fields', '')
            }
            break
except Exception as e:
    alert_data["error"] = str(e)

print(json.dumps(alert_data))
PYEOF
)

# Export as JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "alert_analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/task_result.json
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="