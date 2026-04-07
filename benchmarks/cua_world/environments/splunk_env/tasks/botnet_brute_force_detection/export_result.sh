#!/bin/bash
echo "=== Exporting botnet_brute_force_detection result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess, re

# Load Baselines
try:
    with open('/tmp/botnet_initial_saved_searches.json') as f:
        initial_ss = json.load(f)
except:
    initial_ss = []

try:
    with open('/tmp/botnet_initial_dashboards.json') as f:
        initial_dashboards = json.load(f)
except:
    initial_dashboards = []

# Fetch Current Saved Searches
ss_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

new_searches = []
target_alert = None
try:
    ss_data = json.loads(ss_result.stdout)
    for entry in ss_data.get('entry', []):
        name = entry.get('name', '')
        content = entry.get('content', {})
        search_obj = {
            "name": name,
            "search": content.get('search', ''),
            "is_scheduled": content.get('is_scheduled', '0') == '1',
            "cron_schedule": content.get('cron_schedule', '')
        }
        
        if name not in initial_ss:
            new_searches.append(search_obj)
            
        # Check if it matches expected alert name (case-insensitive, normalized)
        if name.lower().replace(' ', '_') == 'distributed_brute_force_alert':
            target_alert = search_obj
except Exception as e:
    pass

# Fetch Current Dashboards
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
        xml = entry.get('content', {}).get('eai:data', '')
        panel_count = len(re.findall(r'<panel\b', xml, re.IGNORECASE)) if xml else 0
        
        dash_obj = {
            "name": name,
            "panel_count": panel_count,
            "xml_preview": xml[:1000] if xml else "",
            "has_iplocation": 'iplocation' in xml.lower() if xml else False
        }
        
        if name not in initial_dashboards:
            new_dashboards.append(dash_obj)
            
        # Check if it matches expected dashboard name (case-insensitive, normalized)
        if name.lower().replace(' ', '_') == 'botnet_targeting_dashboard':
            target_dashboard = dash_obj
except Exception as e:
    pass

# Fallbacks if exact named items weren't found but agent created new ones
if not target_alert and new_searches:
    target_alert = new_searches[-1]  # Pick latest new search
if not target_dashboard and new_dashboards:
    target_dashboard = new_dashboards[-1]  # Pick latest new dashboard

output = {
    "target_alert": target_alert,
    "target_dashboard": target_dashboard,
    "total_new_searches": len(new_searches),
    "total_new_dashboards": len(new_dashboards)
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

safe_write_json "$TEMP_JSON" /tmp/botnet_task_result.json
echo "Result saved to /tmp/botnet_task_result.json"
cat /tmp/botnet_task_result.json
echo "=== Export complete ==="