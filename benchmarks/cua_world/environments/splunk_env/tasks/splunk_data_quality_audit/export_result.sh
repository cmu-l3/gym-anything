#!/bin/bash
echo "=== Exporting splunk_data_quality_audit result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the Splunk REST API for all dashboards in the system
echo "Querying Splunk REST API for dashboards..."
DASHBOARDS_TEMP=$(mktemp /tmp/dashboards.XXXXXX.json)
curl -sk -u "admin:SplunkAdmin1!" \
    "https://localhost:8089/servicesNS/-/-/data/ui/views?output_mode=json&count=0" \
    > "$DASHBOARDS_TEMP" 2>/dev/null

# Parse the dashboards using Python to find the target and extract its XML/queries
echo "Analyzing dashboard configurations..."
ANALYSIS=$(python3 - "$DASHBOARDS_TEMP" << 'PYEOF'
import sys, json, re

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    
    target_dash = None
    all_dashboards = []
    
    for entry in data.get('entry', []):
        name = entry.get('name', '')
        all_dashboards.append(name)
        # Case insensitive check, but we will strictly evaluate exact case in the verifier
        if name.lower() == 'data_quality_audit':
            target_dash = entry
            break
            
    if target_dash:
        content = target_dash.get('content', {})
        xml_data = content.get('eai:data', '')
        
        # Extract all <query> tags from the XML
        queries = re.findall(r'<query>(.*?)</query>', xml_data, re.DOTALL)
        
        # Count the number of <panel> tags
        panel_count = len(re.findall(r'<panel\b', xml_data, re.IGNORECASE))
        
        result = {
            "dashboard_found": True,
            "dashboard_name": target_dash.get('name'),
            "panel_count": panel_count,
            "queries": queries,
            "xml_preview": xml_data[:500] if xml_data else ""
        }
    else:
        result = {
            "dashboard_found": False,
            "dashboard_name": "",
            "panel_count": 0,
            "queries": [],
            "xml_preview": "",
            "available_dashboards": all_dashboards
        }
        
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({
        "dashboard_found": False,
        "error": str(e)
    }))
PYEOF
)
rm -f "$DASHBOARDS_TEMP"

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "analysis": ${ANALYSIS},
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "task_end_time": $(date +%s),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="