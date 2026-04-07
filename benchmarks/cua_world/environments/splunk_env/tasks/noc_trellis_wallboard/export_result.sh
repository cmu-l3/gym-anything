#!/bin/bash
echo "=== Exporting noc_trellis_wallboard result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM / debugging
take_screenshot /tmp/task_end_screenshot.png

# Fetch dashboard information via REST API and parse it
echo "Fetching dashboards..."
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

try:
    with open('/tmp/initial_dashboards.json', 'r') as f:
        initial_dashboards = json.load(f)
except:
    initial_dashboards = []

result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/data/ui/views?output_mode=json&count=0'],
    capture_output=True, text=True
)

dashboard_found = False
target_name = "noc_system_health_wallboard"
dashboard_xml = ""
new_dashboards = []

try:
    data = json.loads(result.stdout)
    for entry in data.get('entry', []):
        name = entry.get('name', '')
        # Check if it's the target dashboard (case insensitive matching)
        if name.lower() == target_name.lower():
            dashboard_found = True
            dashboard_xml = entry.get('content', {}).get('eai:data', '')
        
        # Also track any new dashboards created during the session
        if name not in initial_dashboards:
            new_dashboards.append({
                "name": name,
                "xml_preview": entry.get('content', {}).get('eai:data', '')[:500]
            })
except Exception as e:
    pass

output = {
    "dashboard_found": dashboard_found,
    "dashboard_xml": dashboard_xml,
    "new_dashboards": new_dashboards,
    "initial_count": len(initial_dashboards)
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