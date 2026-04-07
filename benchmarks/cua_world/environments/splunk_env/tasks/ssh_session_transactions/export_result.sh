#!/bin/bash
echo "=== Exporting ssh_session_transactions result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess, re

def normalize_name(name):
    return name.lower().replace(' ', '_').replace('-', '_')

try:
    with open('/tmp/ssh_session_initial_saved_searches.json') as f:
        initial_ss = json.load(f)
except:
    initial_ss = []

try:
    with open('/tmp/ssh_session_initial_dashboards.json') as f:
        initial_dashboards = json.load(f)
except:
    initial_dashboards = []

# All saved searches
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
                "normalized_name": normalize_name(name),
                "search": entry.get('content', {}).get('search', ''),
                "updated": entry.get('updated', '')
            })
except Exception as e:
    pass

# All dashboards
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
                "normalized_name": normalize_name(name),
                "panel_count": panel_count,
                "xml_preview": xml[:1000] if xml else "",
                "updated": entry.get('updated', '')
            })
except Exception as e:
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

safe_write_json "$TEMP_JSON" /tmp/ssh_session_transactions_result.json
echo "Result saved to /tmp/ssh_session_transactions_result.json"
cat /tmp/ssh_session_transactions_result.json
echo "=== Export complete ==="