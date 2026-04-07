#!/bin/bash
echo "=== Exporting optimize_dashboard_base_searches result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Fetch dashboard definition via Splunk REST API
TEMP_API_RES=$(mktemp /tmp/api_res.XXXXXX.json)
curl -sk -u admin:SplunkAdmin1! "https://localhost:8089/servicesNS/admin/search/data/ui/views/Security_Executive_Overview?output_mode=json" > "$TEMP_API_RES" 2>/dev/null

# Parse the XML data from the API response
ANALYSIS=$(python3 - "$TEMP_API_RES" << 'PYEOF'
import sys, json

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    
    entries = data.get('entry', [])
    if entries:
        xml_data = entries[0].get('content', {}).get('eai:data', '')
        updated_time = entries[0].get('updated', '')
        print(json.dumps({
            "dashboard_found": True,
            "xml_data": xml_data,
            "updated_time": updated_time
        }))
    else:
        print(json.dumps({
            "dashboard_found": False,
            "xml_data": "",
            "updated_time": ""
        }))
except Exception as e:
    print(json.dumps({
        "dashboard_found": False,
        "error": str(e)
    }))
PYEOF
)
rm -f "$TEMP_API_RES"

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