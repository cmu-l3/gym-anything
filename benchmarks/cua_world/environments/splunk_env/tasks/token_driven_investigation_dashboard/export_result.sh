#!/bin/bash
echo "=== Exporting token_driven_investigation_dashboard result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query the Splunk REST API to extract dashboards and analyze them
echo "Checking Splunk for new dashboards..."
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

# Load baselines to determine what's new
try:
    with open('/tmp/initial_dashboards.json', 'r') as f:
        initial_dashboards = json.load(f)
except:
    initial_dashboards = []

# Fetch all dashboards in the system
dash_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/data/ui/views?output_mode=json&count=0'],
    capture_output=True, text=True
)

new_dashboards = []
target_dashboard = None

try:
    dash_data = json.loads(dash_result.stdout)
    for entry in dash_data.get('entry', []):
        name = entry.get('name', '')
        xml_content = entry.get('content', {}).get('eai:data', '')
        
        # Determine if it's the target dashboard by name (robust to case and spacing)
        is_target_name = name.lower().replace(' ', '_') == 'ip_investigation_tool'
        
        # Track it if it's new OR matches our target name
        if name not in initial_dashboards or is_target_name:
            dash_info = {
                "name": name,
                "xml": xml_content
            }
            new_dashboards.append(dash_info)
            if is_target_name:
                target_dashboard = dash_info
except Exception as e:
    pass

# If the user named it wrong, evaluate the most recently created new dashboard as a fallback
if not target_dashboard and new_dashboards:
    target_dashboard = new_dashboards[-1]

result = {
    "new_dashboards_count": len(new_dashboards),
    "target_dashboard": target_dashboard
}
print(json.dumps(result))
PYEOF
)

# Export the collected data
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="