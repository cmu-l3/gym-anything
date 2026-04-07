#!/bin/bash
echo "=== Exporting ecommerce_conversion_analytics result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query Splunk REST API for the required artifacts
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess, re

def normalize_name(n):
    return n.lower().replace(' ', '_').replace('-', '_')

# Get baseline artifacts
try:
    with open('/tmp/baseline_searches.json') as f:
        baseline_searches = json.load(f)
except:
    baseline_searches = []

try:
    with open('/tmp/baseline_dashboards.json') as f:
        baseline_dashboards = json.load(f)
except:
    baseline_dashboards = []

# Fetch all saved searches
ss_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

report = None
try:
    ss_data = json.loads(ss_result.stdout)
    for entry in ss_data.get('entry', []):
        name = entry.get('name', '')
        if normalize_name(name) == 'category_conversion_rate':
            report = {
                "name": name,
                "search": entry.get('content', {}).get('search', ''),
                "is_new": name not in baseline_searches
            }
            break
except Exception as e:
    pass

# Fetch all dashboards
dash_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/data/ui/views?output_mode=json&count=0'],
    capture_output=True, text=True
)

dashboard = None
try:
    dash_data = json.loads(dash_result.stdout)
    for entry in dash_data.get('entry', []):
        name = entry.get('name', '')
        if normalize_name(name) == 'business_kpi_dashboard':
            xml = entry.get('content', {}).get('eai:data', '')
            panel_count = len(re.findall(r'<panel\b', xml, re.IGNORECASE)) if xml else 0
            dashboard = {
                "name": name,
                "xml": xml,
                "panel_count": panel_count,
                "is_new": name not in baseline_dashboards
            }
            break
except Exception as e:
    pass

output = {
    "report": report,
    "dashboard": dashboard
}
print(json.dumps(output))
PYEOF
)

# Export to final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/ecommerce_conversion_result.json
echo "Result saved to /tmp/ecommerce_conversion_result.json"
cat /tmp/ecommerce_conversion_result.json
echo "=== Export complete ==="