#!/bin/bash
echo "=== Exporting interactive_geo_dashboard result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve current dashboards from Splunk REST API
echo "Fetching dashboard data..."
VIEWS_TEMP=$(mktemp /tmp/views.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/data/ui/views?output_mode=json&count=0" \
    > "$VIEWS_TEMP" 2>/dev/null

# Parse results and extract the specific dashboard's XML
ANALYSIS=$(python3 - "$VIEWS_TEMP" << 'PYEOF'
import sys, json

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    entries = data.get('entry', [])

    try:
        with open('/tmp/initial_dashboards.json', 'r') as f:
            initial_names = json.load(f)
    except:
        initial_names = []

    target_dashboard_name = "Geospatial_Auth_Activity"
    dashboard_found = False
    dashboard_xml = ""
    is_newly_created = False
    new_dashboards = []

    for entry in entries:
        name = entry.get('name', '')
        content = entry.get('content', {})
        
        if name not in initial_names:
            new_dashboards.append(name)

        # Splunk handles names case-sensitively in the API, but users might alter casing.
        if name.lower() == target_dashboard_name.lower():
            dashboard_found = True
            dashboard_xml = content.get('eai:data', '')
            is_newly_created = (name not in initial_names)
            break

    # If the user named it slightly wrong but created a new dashboard, provide the XML 
    # of the first new dashboard for partial credit potential.
    if not dashboard_found and new_dashboards:
        for entry in entries:
            name = entry.get('name', '')
            if name == new_dashboards[0]:
                dashboard_xml = entry.get('content', {}).get('eai:data', '')
                break

    result = {
        "dashboard_found": dashboard_found,
        "is_newly_created": is_newly_created,
        "dashboard_xml": dashboard_xml,
        "new_dashboards": new_dashboards,
        "total_dashboards": len(entries)
    }
    print(json.dumps(result))

except Exception as e:
    print(json.dumps({
        "dashboard_found": False,
        "is_newly_created": False,
        "dashboard_xml": "",
        "new_dashboards": [],
        "total_dashboards": 0,
        "error": str(e)
    }))
PYEOF
)
rm -f "$VIEWS_TEMP"

# Create final export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/dashboard_task_result.json

echo "Result saved to /tmp/dashboard_task_result.json"
cat /tmp/dashboard_task_result.json
echo "=== Export complete ==="