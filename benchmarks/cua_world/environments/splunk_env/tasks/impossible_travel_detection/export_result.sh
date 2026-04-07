#!/bin/bash
echo "=== Exporting impossible_travel_detection result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Perform REST API queries and output analysis JSON directly
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess, re

# Load baselines
try:
    with open('/tmp/initial_saved_searches.json') as f:
        initial_ss = json.load(f)
except:
    initial_ss = []

try:
    with open('/tmp/initial_dashboards.json') as f:
        initial_dashboards = json.load(f)
except:
    initial_dashboards = []

def normalize_name(name):
    return name.lower().replace(' ', '_').replace('-', '_')

# 1. Evaluate Saved Searches (Reports/Alerts)
ss_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

found_report = False
report_search = ""
report_name = ""
is_new_report = False

try:
    ss_data = json.loads(ss_result.stdout)
    for entry in ss_data.get('entry', []):
        name = entry.get('name', '')
        norm_name = normalize_name(name)
        if norm_name == "impossible_travel_detection":
            found_report = True
            report_name = name
            report_search = entry.get('content', {}).get('search', '')
            is_new_report = name not in initial_ss
            break
except Exception as e:
    pass

# 2. Evaluate Dashboards
dash_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/data/ui/views?output_mode=json&count=0'],
    capture_output=True, text=True
)

found_dashboard = False
dashboard_name = ""
dashboard_xml = ""
panel_count = 0
has_geostats = False
is_new_dashboard = False

try:
    dash_data = json.loads(dash_result.stdout)
    for entry in dash_data.get('entry', []):
        name = entry.get('name', '')
        norm_name = normalize_name(name)
        if norm_name == "geo_security_monitoring":
            found_dashboard = True
            dashboard_name = name
            is_new_dashboard = name not in initial_dashboards
            xml = entry.get('content', {}).get('eai:data', '')
            if xml:
                dashboard_xml = xml
                # Count <panel> blocks in the XML
                panel_count = len(re.findall(r'<panel\b', xml, re.IGNORECASE))
                has_geostats = 'geostats' in xml.lower()
            break
except Exception as e:
    pass

output = {
    "report_found": found_report,
    "report_name": report_name,
    "report_search": report_search,
    "is_new_report": is_new_report,
    "dashboard_found": found_dashboard,
    "dashboard_name": dashboard_name,
    "dashboard_panels": panel_count,
    "dashboard_has_geostats": has_geostats,
    "is_new_dashboard": is_new_dashboard
}
print(json.dumps(output))
PYEOF
)

# Safely save the output to the container
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/impossible_travel_result.json
echo "Result saved to /tmp/impossible_travel_result.json"
cat /tmp/impossible_travel_result.json
echo "=== Export complete ==="