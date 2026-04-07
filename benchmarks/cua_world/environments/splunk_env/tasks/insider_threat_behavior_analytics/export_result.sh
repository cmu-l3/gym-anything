#!/bin/bash
echo "=== Exporting insider_threat_behavior_analytics result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM / debugging
take_screenshot /tmp/task_end_screenshot.png

# Retrieve current dashboards via REST API and analyze XML
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

try:
    with open('/tmp/ita_initial_dashboards.json') as f:
        initial_dashboards = json.load(f)
except:
    initial_dashboards = []

dash_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/data/ui/views?output_mode=json&count=0'],
    capture_output=True, text=True
)

new_dashboards = []
target_dashboard_xml = ""
found_target = False
target_name = "Insider_Threat_Analytics"

try:
    dash_data = json.loads(dash_result.stdout)
    for entry in dash_data.get('entry', []):
        name = entry.get('name', '')
        
        # Check if it's the target dashboard (case-insensitive)
        if name.lower() == target_name.lower():
            found_target = True
            target_dashboard_xml = entry.get('content', {}).get('eai:data', '')
            
        # Also track newly created dashboards in case the agent used a slightly different name
        if name not in initial_dashboards:
            xml_data = entry.get('content', {}).get('eai:data', '')
            new_dashboards.append({
                "name": name,
                "xml_data": xml_data
            })
            
            # If target dashboard name wasn't exact match but it's new and contains the core name, use it
            if not found_target and "insider_threat" in name.lower():
                found_target = True
                target_dashboard_xml = xml_data

except Exception as e:
    pass

output = {
    "new_dashboards": new_dashboards,
    "found_target": found_target,
    "target_dashboard_xml": target_dashboard_xml
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

safe_write_json "$TEMP_JSON" /tmp/insider_threat_behavior_analytics_result.json
echo "Result saved to /tmp/insider_threat_behavior_analytics_result.json"
cat /tmp/insider_threat_behavior_analytics_result.json
echo "=== Export complete ==="