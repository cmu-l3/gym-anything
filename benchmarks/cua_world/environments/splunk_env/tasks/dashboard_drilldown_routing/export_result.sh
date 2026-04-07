#!/bin/bash
echo "=== Exporting dashboard_drilldown_routing result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

detailed_name = "Detailed_IP_Investigation"
summary_name = "Global_Threat_Overview"

def get_dashboard_xml(name):
    # Search for the dashboard by exact name
    result = subprocess.run(
        ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
         f'https://localhost:8089/servicesNS/-/-/data/ui/views/{name}?output_mode=json'],
        capture_output=True, text=True
    )
    try:
        data = json.loads(result.stdout)
        entries = data.get('entry', [])
        if entries:
            return entries[0].get('content', {}).get('eai:data', '')
    except:
        pass
    
    # Try lowercase naming as fallback (Splunk URL routes often lowercase IDs)
    result = subprocess.run(
        ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
         f'https://localhost:8089/servicesNS/-/-/data/ui/views/{name.lower()}?output_mode=json'],
        capture_output=True, text=True
    )
    try:
        data = json.loads(result.stdout)
        entries = data.get('entry', [])
        if entries:
            return entries[0].get('content', {}).get('eai:data', '')
    except:
        pass
    
    return ""

detailed_xml = get_dashboard_xml(detailed_name)
summary_xml = get_dashboard_xml(summary_name)

output = {
    "detailed_dashboard_xml": detailed_xml,
    "summary_dashboard_xml": summary_xml
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

safe_write_json "$TEMP_JSON" /tmp/dashboard_drilldown_routing_result.json
echo "Result saved to /tmp/dashboard_drilldown_routing_result.json"
cat /tmp/dashboard_drilldown_routing_result.json
echo "=== Export complete ==="