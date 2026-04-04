#!/bin/bash
echo "=== Exporting soc_executive_dashboard result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess, re

try:
    with open('/tmp/soc_exec_initial_saved_searches.json') as f:
        initial_ss = json.load(f)
except:
    initial_ss = []

try:
    with open('/tmp/soc_exec_initial_dashboards.json') as f:
        initial_dashboards = json.load(f)
except:
    initial_dashboards = []

def has_threshold(search_text):
    low = search_text.lower()
    patterns = [
        r'where\s+count\s*[><=]+\s*\d+',
        r'count\s*[><=]+\s*\d+',
        r'where\s+\w+\s*[><=]+\s*\d+',
    ]
    for p in patterns:
        if re.search(p, low):
            return True
    return False

# All new dashboards
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
            refs_security = 'security_logs' in xml.lower() if xml else False
            new_dashboards.append({
                "name": name,
                "panel_count": panel_count,
                "refs_security_logs": refs_security,
            })
except:
    pass

# All new scheduled alerts
ss_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

new_alerts = []
try:
    ss_data = json.loads(ss_result.stdout)
    for entry in ss_data.get('entry', []):
        name = entry.get('name', '')
        if name not in initial_ss:
            content = entry.get('content', {})
            search_text = content.get('search', '')
            is_scheduled = content.get('is_scheduled', '0') == '1'
            cron = content.get('cron_schedule', '')
            new_alerts.append({
                "name": name,
                "search": search_text,
                "is_scheduled": is_scheduled,
                "cron_schedule": cron,
                "has_threshold": has_threshold(search_text),
            })
except:
    pass

output = {
    "new_dashboards": new_dashboards,
    "new_alerts": new_alerts,
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

safe_write_json "$TEMP_JSON" /tmp/soc_executive_dashboard_result.json
echo "Result saved to /tmp/soc_executive_dashboard_result.json"
cat /tmp/soc_executive_dashboard_result.json
echo "=== Export complete ==="
