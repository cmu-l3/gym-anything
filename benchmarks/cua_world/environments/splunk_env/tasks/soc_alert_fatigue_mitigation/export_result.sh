#!/bin/bash
echo "=== Exporting soc_alert_fatigue_mitigation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query Splunk API for internal configuration state
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

try:
    with open('/tmp/soc_alert_initial_saved_searches.json') as f:
        initial_ss = json.load(f)
except:
    initial_ss = []

result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

target_alert = None
new_searches = []
try:
    data = json.loads(result.stdout)
    for entry in data.get('entry', []):
        name = entry.get('name', '')
        content = entry.get('content', {})
        
        # Track newly created objects
        if name not in initial_ss:
            new_searches.append(name)
            
        # Check if it matches our target alert name (case-insensitive, underscore normalized)
        norm_name = name.lower().replace(' ', '_').replace('-', '_')
        if norm_name == 'throttled_ssh_brute_force':
            target_alert = {
                "name": name,
                "search": content.get('search', ''),
                "is_scheduled": str(content.get('is_scheduled', '0')) in ['1', 'True', 'true'],
                "cron_schedule": content.get('cron_schedule', ''),
                "alert.suppress": str(content.get('alert.suppress', '0')) in ['1', 'True', 'true'],
                "alert.suppress.fields": content.get('alert.suppress.fields', ''),
                "alert.suppress.period": content.get('alert.suppress.period', '')
            }
except Exception as e:
    pass

output = {
    "target_alert": target_alert,
    "new_searches": new_searches
}
print(json.dumps(output))
PYEOF
)

# Compile results securely into temporary file before saving
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/soc_alert_fatigue_result.json
echo "Result saved to /tmp/soc_alert_fatigue_result.json"
cat /tmp/soc_alert_fatigue_result.json
echo "=== Export complete ==="