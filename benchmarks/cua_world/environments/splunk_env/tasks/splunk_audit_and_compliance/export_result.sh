#!/bin/bash
echo "=== Exporting splunk_audit_and_compliance result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Extract and analyze the objects via REST API
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess, re

def normalize_name(name):
    return name.lower().replace(' ', '_').replace('-', '_')

# Load baseline states
try:
    with open('/tmp/initial_dashboards.json') as f:
        initial_dashboards = json.load(f)
except:
    initial_dashboards = []

try:
    with open('/tmp/initial_searches.json') as f:
        initial_searches = json.load(f)
except:
    initial_searches = []

# Fetch current dashboards (views)
res_views = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', 'https://localhost:8089/servicesNS/-/-/data/ui/views?output_mode=json&count=0'],
    capture_output=True, text=True
)
dashboards = []
try:
    for e in json.loads(res_views.stdout).get('entry', []):
        dashboards.append({
            'name': e.get('name', ''),
            'xml': e.get('content', {}).get('eai:data', '')
        })
except:
    pass

# Fetch current saved searches (alerts)
res_searches = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', 'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)
searches = []
try:
    for e in json.loads(res_searches.stdout).get('entry', []):
        c = e.get('content', {})
        searches.append({
            'name': e.get('name', ''),
            'search': c.get('search', ''),
            'is_scheduled': c.get('is_scheduled', '0') == '1',
            'cron_schedule': c.get('cron_schedule', '')
        })
except:
    pass

# Targets
target_dash_norm = "splunk_usage_audit"
target_alert_norm = "data_exfiltration_via_search"
export_keywords = ["outputcsv", "outputlookup", "export"]

dash_found = False
dash_panels = 0
dash_filters_system = False
dash_is_new = False
dash_actual_name = ""

for d in dashboards:
    if normalize_name(d['name']) == target_dash_norm:
        dash_found = True
        dash_actual_name = d['name']
        dash_is_new = d['name'] not in initial_dashboards
        xml = d['xml'] or ""
        # Count panel tags
        dash_panels = len(re.findall(r'<panel\b', xml, re.IGNORECASE))
        # Check if the system user filter is present anywhere in the XML definition
        dash_filters_system = 'splunk-system-user' in xml.lower()
        break

alert_found = False
alert_queries_audit = False
alert_has_export_kw = False
alert_is_scheduled = False
alert_is_new = False
alert_actual_name = ""
alert_search_preview = ""

for s in searches:
    if normalize_name(s['name']) == target_alert_norm:
        alert_found = True
        alert_actual_name = s['name']
        alert_is_new = s['name'] not in initial_searches
        search_str = s['search'].lower()
        alert_search_preview = s['search'][:100]
        alert_queries_audit = '_audit' in search_str
        alert_has_export_kw = any(kw in search_str for kw in export_keywords)
        alert_is_scheduled = s['is_scheduled'] or bool(s['cron_schedule'])
        break

output = {
    "dashboard": {
        "found": dash_found,
        "is_new": dash_is_new,
        "panels": dash_panels,
        "filters_system_user": dash_filters_system,
        "actual_name": dash_actual_name
    },
    "alert": {
        "found": alert_found,
        "is_new": alert_is_new,
        "queries_audit": alert_queries_audit,
        "has_export_kw": alert_has_export_kw,
        "is_scheduled": alert_is_scheduled,
        "actual_name": alert_actual_name,
        "search_preview": alert_search_preview
    }
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

safe_write_json "$TEMP_JSON" /tmp/splunk_audit_task_result.json
echo "Result saved to /tmp/splunk_audit_task_result.json"
cat /tmp/splunk_audit_task_result.json
echo "=== Export complete ==="