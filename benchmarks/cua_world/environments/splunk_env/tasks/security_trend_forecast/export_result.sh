#!/bin/bash
echo "=== Exporting security_trend_forecast result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Fetch current saved searches and dashboards via Splunk REST API
SS_TEMP=$(mktemp /tmp/ss.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches?output_mode=json&count=0" \
    > "$SS_TEMP" 2>/dev/null

DASH_TEMP=$(mktemp /tmp/dash.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/data/ui/views?output_mode=json&count=0" \
    > "$DASH_TEMP" 2>/dev/null

# Python script to compare and identify the created artifacts
ANALYSIS=$(python3 - "$SS_TEMP" "$DASH_TEMP" << 'PYEOF'
import sys, json, re

def normalize_name(name):
    return name.lower().replace(' ', '_').replace('-', '_')

# Load baselines
try:
    with open('/tmp/stf_initial_saved_searches.json') as f:
        initial_ss = json.load(f)
except:
    initial_ss = []

try:
    with open('/tmp/stf_initial_dashboards.json') as f:
        initial_dashboards = json.load(f)
except:
    initial_dashboards = []

# Load current API data
try:
    with open(sys.argv[1], 'r') as f:
        ss_data = json.load(f)
except:
    ss_data = {}

try:
    with open(sys.argv[2], 'r') as f:
        dash_data = json.load(f)
except:
    dash_data = {}

new_searches = []
found_target_search = False
target_search_info = {}

# Process saved searches
for entry in ss_data.get('entry', []):
    name = entry.get('name', '')
    if name not in initial_ss:
        content = entry.get('content', {})
        search_info = {
            "name": name,
            "normalized_name": normalize_name(name),
            "search": content.get('search', ''),
            "is_scheduled": content.get('is_scheduled', '0') == '1',
            "cron_schedule": content.get('cron_schedule', '')
        }
        new_searches.append(search_info)
        
        # Check against expected name
        if normalize_name(name) == "auth_failure_forecast":
            found_target_search = True
            target_search_info = search_info

new_dashboards = []
found_target_dashboard = False
target_dashboard_info = {}

# Process dashboards
for entry in dash_data.get('entry', []):
    name = entry.get('name', '')
    if name not in initial_dashboards:
        content = entry.get('content', {})
        xml = content.get('eai:data', '')
        
        # Count panels in XML
        panel_count = len(re.findall(r'<panel\b', xml, re.IGNORECASE)) if xml else 0
        dash_info = {
            "name": name,
            "normalized_name": normalize_name(name),
            "panel_count": panel_count,
            "xml_preview": xml[:500] if xml else ""
        }
        new_dashboards.append(dash_info)
        
        # Check against expected dashboard name
        if normalize_name(name) == "security_trend_forecast":
            found_target_dashboard = True
            target_dashboard_info = dash_info

output = {
    "new_searches": new_searches,
    "found_target_search": found_target_search,
    "target_search_info": target_search_info,
    "new_dashboards": new_dashboards,
    "found_target_dashboard": found_target_dashboard,
    "target_dashboard_info": target_dashboard_info
}
print(json.dumps(output))
PYEOF
)
rm -f "$SS_TEMP" "$DASH_TEMP"

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/security_trend_forecast_result.json
echo "Result saved to /tmp/security_trend_forecast_result.json"
cat /tmp/security_trend_forecast_result.json
echo "=== Export complete ==="