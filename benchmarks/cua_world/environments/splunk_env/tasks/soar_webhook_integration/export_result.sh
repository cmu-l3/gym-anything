#!/bin/bash
echo "=== Exporting soar_webhook_integration result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Extract and analyze the configurations using Python
echo "Analyzing Splunk artifacts via REST API..."
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

try:
    with open('/tmp/soar_initial_alerts.json') as f:
        initial_alerts = json.load(f)
except:
    initial_alerts = []

try:
    with open('/tmp/soar_initial_dashboards.json') as f:
        initial_dashboards = json.load(f)
except:
    initial_dashboards = []

def normalize_name(name):
    return name.lower().replace(' ', '_').replace('-', '_')

# --- 1. Fetch and process Saved Searches (Alerts) ---
ss_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

found_alert = False
alert_data = {}

try:
    ss_data = json.loads(ss_result.stdout)
    for entry in ss_data.get('entry', []):
        name = entry.get('name', '')
        if normalize_name(name) == 'brute_force_webhook_alert':
            found_alert = True
            content = entry.get('content', {})
            alert_data = {
                'name': name,
                'search': content.get('search', ''),
                'is_scheduled': content.get('is_scheduled', 0),
                'cron_schedule': content.get('cron_schedule', ''),
                'action_webhook': content.get('action.webhook', 0),
                'webhook_url': content.get('action.webhook.param.url', ''),
                'suppress': content.get('alert.suppress', 0),
                'suppress_fields': content.get('alert.suppress.fields', ''),
                'suppress_period': content.get('alert.suppress.period', '')
            }
            break
except Exception as e:
    pass

# --- 2. Fetch and process Dashboards (Views) ---
dash_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/data/ui/views?output_mode=json&count=0'],
    capture_output=True, text=True
)

found_dashboard = False
dashboard_data = {}

try:
    dash_data = json.loads(dash_result.stdout)
    for entry in dash_data.get('entry', []):
        name = entry.get('name', '')
        if normalize_name(name) == 'soar_integration_health':
            found_dashboard = True
            content = entry.get('content', {})
            dashboard_data = {
                'name': name,
                'eai_data': content.get('eai:data', '')
            }
            break
except Exception as e:
    pass

# Package output
output = {
    'found_alert': found_alert,
    'alert_is_new': found_alert and alert_data.get('name') not in initial_alerts,
    'alert_data': alert_data,
    'found_dashboard': found_dashboard,
    'dashboard_is_new': found_dashboard and dashboard_data.get('name') not in initial_dashboards,
    'dashboard_data': dashboard_data
}
print(json.dumps(output))
PYEOF
)

# Write output to file safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="