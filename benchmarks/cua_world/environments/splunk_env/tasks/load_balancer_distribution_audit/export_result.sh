#!/bin/bash
echo "=== Exporting load_balancer_distribution_audit result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
DURATION=$((TASK_END - TASK_START))

# Use Python to extract all new Splunk knowledge objects cleanly
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess, re

try:
    with open('/tmp/baseline_saved_searches.json') as f:
        initial_ss = json.load(f)
except:
    initial_ss = []

try:
    with open('/tmp/baseline_dashboards.json') as f:
        initial_dashboards = json.load(f)
except:
    initial_dashboards = []

# Fetch current saved searches (alerts/reports)
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
            new_alerts.append({
                "name": name,
                "search": content.get('search', ''),
                "is_scheduled": content.get('is_scheduled', '0') == '1',
                "cron_schedule": content.get('cron_schedule', '')
            })
except Exception as e:
    pass

# Fetch current dashboards
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
            
            # Extract panel searches from XML manually to pass to verifier
            panel_searches = re.findall(r'<query>(.*?)</query>', xml, re.DOTALL | re.IGNORECASE)
            # Fallback if using 'searchString' in older SimpleXML
            if not panel_searches:
                panel_searches = re.findall(r'<searchString>(.*?)</searchString>', xml, re.DOTALL | re.IGNORECASE)

            new_dashboards.append({
                "name": name,
                "xml_preview": xml[:500] if xml else "",
                "panel_searches": [s.strip() for s in panel_searches]
            })
except Exception as e:
    pass

output = {
    "new_alerts": new_alerts,
    "new_dashboards": new_dashboards
}
print(json.dumps(output))
PYEOF
)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "task_duration_seconds": ${DURATION},
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/load_balancer_audit_result.json
echo "Result saved to /tmp/load_balancer_audit_result.json"
cat /tmp/load_balancer_audit_result.json
echo "=== Export complete ==="