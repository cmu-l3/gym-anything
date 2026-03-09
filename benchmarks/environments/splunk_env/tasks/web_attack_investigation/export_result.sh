#!/bin/bash
echo "=== Exporting web_attack_investigation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess, re

try:
    with open('/tmp/web_attack_initial_saved_searches.json') as f:
        initial_ss = json.load(f)
except:
    initial_ss = []

try:
    with open('/tmp/web_attack_initial_dashboards.json') as f:
        initial_dashboards = json.load(f)
except:
    initial_dashboards = []

# All new saved searches
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
            new_searches.append({
                "name": name,
                "search": entry.get('content', {}).get('search', ''),
            })
except:
    pass

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
            refs_logs = ('security_logs' in xml.lower() or 'web_logs' in xml.lower() or 'index=' in xml.lower()) if xml else False
            new_dashboards.append({
                "name": name,
                "panel_count": panel_count,
                "refs_logs": refs_logs,
                "xml_preview": xml[:300] if xml else "",
            })
except:
    pass

output = {
    "new_searches": new_searches,
    "new_dashboards": new_dashboards,
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

safe_write_json "$TEMP_JSON" /tmp/web_attack_investigation_result.json
echo "Result saved to /tmp/web_attack_investigation_result.json"
cat /tmp/web_attack_investigation_result.json
echo "=== Export complete ==="
