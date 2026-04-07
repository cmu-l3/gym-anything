#!/bin/bash
echo "=== Exporting soc_shift_handoff_dashboard result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

echo "Extracting dashboard configurations from Splunk REST API..."

# Extract the specific target dashboard
DASHBOARD_TEMP=$(mktemp /tmp/dash.XXXXXX.json)
curl -sk -u "admin:SplunkAdmin1!" \
    "https://localhost:8089/servicesNS/-/-/data/ui/views/SOC_Shift_Handoff?output_mode=json" \
    > "$DASHBOARD_TEMP" 2>/dev/null

# Safely parse the exact target dashboard using Python
TARGET_ANALYSIS=$(python3 - "$DASHBOARD_TEMP" << 'PYEOF'
import sys, json

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    
    entries = data.get('entry', [])
    if not entries:
        print(json.dumps({"exists": False, "xml": ""}))
    else:
        # eai:data contains the raw XML of the dashboard
        xml_content = entries[0].get('content', {}).get('eai:data', '')
        print(json.dumps({
            "exists": True, 
            "xml": xml_content,
            "author": entries[0].get('author', ''),
            "updated": entries[0].get('updated', '')
        }))
except Exception as e:
    print(json.dumps({"exists": False, "xml": "", "error": str(e)}))
PYEOF
)
rm -f "$DASHBOARD_TEMP"

# Fallback: Extract all views in case it was saved under a slightly different name
ALL_DASH_TEMP=$(mktemp /tmp/alldash.XXXXXX.json)
curl -sk -u "admin:SplunkAdmin1!" \
    "https://localhost:8089/servicesNS/-/-/data/ui/views?output_mode=json&count=0" \
    > "$ALL_DASH_TEMP" 2>/dev/null

ALL_ANALYSIS=$(python3 - "$ALL_DASH_TEMP" << 'PYEOF'
import sys, json

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    
    views = []
    # Filter out internal Splunk dashboards to keep JSON size manageable
    ignore_list = ['search', 'home', 'inputs', 'data_models', 'alerts', 'dashboards']
    
    for entry in data.get('entry', []):
        name = entry.get('name', '')
        if name not in ignore_list and not name.startswith('_'):
            views.append({
                "name": name,
                "xml": entry.get('content', {}).get('eai:data', '')
            })
    print(json.dumps(views))
except Exception as e:
    print("[]")
PYEOF
)
rm -f "$ALL_DASH_TEMP"

# Combine into a final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_dashboard": ${TARGET_ANALYSIS},
    "all_dashboards": ${ALL_ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
safe_write_json "$TEMP_JSON" /tmp/soc_shift_handoff_result.json

echo "Result saved to /tmp/soc_shift_handoff_result.json"
echo "=== Export complete ==="