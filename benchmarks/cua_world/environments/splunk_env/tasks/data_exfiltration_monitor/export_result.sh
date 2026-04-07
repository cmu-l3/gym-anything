#!/bin/bash
echo "=== Exporting data_exfiltration_monitor result ==="

source /workspace/scripts/task_utils.sh

# Record end time and take final screenshot
date +%s > /tmp/task_end_time.txt
take_screenshot /tmp/task_final.png

# Fetch and analyze the configurations using Python
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess, re

def get_splunk_data(endpoint):
    try:
        res = subprocess.run(
            ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', f'https://localhost:8089{endpoint}'],
            capture_output=True, text=True, timeout=10
        )
        return json.loads(res.stdout).get('entry', [])
    except Exception as e:
        return []

searches = get_splunk_data('/servicesNS/-/-/saved/searches?output_mode=json&count=0')
dashboards = get_splunk_data('/servicesNS/-/-/data/ui/views?output_mode=json&count=0')

report_data = {'found': False, 'search': ''}
alert_data = {'found': False, 'search': '', 'is_scheduled': False}
dash_data = {'found': False, 'xml': '', 'panel_count': 0}

for s in searches:
    name = s.get('name', '')
    content = s.get('content', {})
    search_query = content.get('search', '')
    
    if name.lower() == 'high_volume_data_transfers':
        report_data = {
            'found': True,
            'search': search_query
        }
    elif name.lower() == 'exfiltration_spike_alert':
        is_scheduled = content.get('is_scheduled', '0') == '1' or content.get('cron_schedule', '') != ''
        alert_data = {
            'found': True,
            'search': search_query,
            'is_scheduled': is_scheduled
        }

for d in dashboards:
    name = d.get('name', '')
    if name.lower() == 'data_exfiltration_dashboard':
        xml = d.get('content', {}).get('eai:data', '')
        panel_count = len(re.findall(r'<panel\b', xml, re.IGNORECASE)) if xml else 0
        dash_data = {
            'found': True,
            'xml': xml,
            'panel_count': panel_count
        }

output = {
    "report": report_data,
    "alert": alert_data,
    "dashboard": dash_data
}
print(json.dumps(output))
PYEOF
)

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/data_exfiltration_result.json
echo "Result saved to /tmp/data_exfiltration_result.json"
cat /tmp/data_exfiltration_result.json
echo "=== Export complete ==="