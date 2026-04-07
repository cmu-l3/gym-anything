#!/bin/bash
echo "=== Exporting low_and_slow_password_spray result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess, re

# Load Baselines
try:
    with open('/tmp/ps_initial_searches.json') as f:
        initial_ss = json.load(f)
except:
    initial_ss = []

try:
    with open('/tmp/ps_initial_dashboards.json') as f:
        initial_dashboards = json.load(f)
except:
    initial_dashboards = []

# Fetch current saved searches
ss_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

new_searches = []
try:
    ss_data = json.loads(ss_result.stdout)
    for entry in ss_data.get('entry', []):
        name = entry.get('name', '')
        if name not in initial_ss:
            content = entry.get('content', {})
            new_searches.append({
                "name": name,
                "search": content.get('search', ''),
                "is_scheduled": content.get('is_scheduled', '0') == '1' or content.get('cron_schedule', '') != '',
                "cron_schedule": content.get('cron_schedule', ''),
            })
except Exception as e:
    pass

# Fetch current dashboards (views)
dash_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/data/ui/views?output_mode=json&count=0'],
    capture_output=True, text=True
)

new_dashboards = []
try:
    dash_data = json.loads(dash_result.stdout)
    for entry in dash_data.get('entry', []):
        name = entry.get('name', '')
        if name not in initial_dashboards:
            xml = entry.get('content', {}).get('eai:data', '')
            panel_count = len(re.findall(r'<panel\b', xml, re.IGNORECASE)) if xml else 0
            new_dashboards.append({
                "name": name,
                "panel_count": panel_count,
                "xml_preview": xml[:500] if xml else "",
            })
except Exception as e:
    pass

output = {
    "new_searches": new_searches,
    "new_dashboards": new_dashboards,
    "initial_search_count": len(initial_ss),
    "initial_dash_count": len(initial_dashboards)
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

safe_write_json "$TEMP_JSON" /tmp/password_spray_result.json
echo "Result saved to /tmp/password_spray_result.json"
cat /tmp/password_spray_result.json
echo "=== Export complete ==="