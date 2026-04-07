#!/bin/bash
echo "=== Exporting log_source_coverage_audit result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Use Python to gather all required data from Splunk REST API
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess, os

# 1. Load Baselines
try:
    with open('/tmp/audit_initial_saved_searches.json') as f:
        initial_ss = json.load(f)
except:
    initial_ss = []

try:
    with open('/tmp/audit_initial_dashboards.json') as f:
        initial_dashboards = json.load(f)
except:
    initial_dashboards = []

# 2. Get Saved Searches
ss_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', 'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

new_searches = []
target_search_found = False
target_search_data = {}

try:
    ss_data = json.loads(ss_result.stdout)
    for entry in ss_data.get('entry', []):
        name = entry.get('name', '')
        content = entry.get('content', {})
        
        if name not in initial_ss:
            new_searches.append(name)
            
        # Check for the specific target search (case-insensitive)
        if name.lower().replace(' ', '_') == 'audit_log_coverage_gaps':
            target_search_found = True
            target_search_data = {
                "name": name,
                "search": content.get('search', ''),
                "is_scheduled": content.get('is_scheduled', '0') == '1',
                "cron_schedule": content.get('cron_schedule', '')
            }
except Exception as e:
    pass

# 3. Get Dashboards
dash_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', 'https://localhost:8089/servicesNS/-/-/data/ui/views?output_mode=json&count=0'],
    capture_output=True, text=True
)

new_dashboards = []
target_dashboard_found = False
target_dashboard_data = {}

try:
    dash_data = json.loads(dash_result.stdout)
    for entry in dash_data.get('entry', []):
        name = entry.get('name', '')
        content = entry.get('content', {})
        
        if name not in initial_dashboards:
            new_dashboards.append(name)
            
        if name.lower().replace(' ', '_') == 'compliance_audit_dashboard':
            target_dashboard_found = True
            target_dashboard_data = {
                "name": name,
                "eai:data": content.get('eai:data', '')
            }
except Exception as e:
    pass

# 4. Check if lookup file has been populated
lookup_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', 'https://localhost:8089/services/search/jobs', 
     '-d', 'search=| inputlookup non_compliant_hosts.csv | stats count', 
     '-d', 'exec_mode=oneshot', '-d', 'output_mode=json'],
    capture_output=True, text=True
)

lookup_count = 0
lookup_query_success = False
try:
    lu_data = json.loads(lookup_result.stdout)
    results = lu_data.get('results', [])
    if results:
        lookup_count = int(results[0].get('count', 0))
        lookup_query_success = True
except Exception as e:
    pass

# Check physical file existence as fallback
physical_lookup_exists = False
try:
    out = subprocess.run(['find', '/opt/splunk/etc/', '-name', 'non_compliant_hosts.csv'], capture_output=True, text=True)
    if out.stdout.strip():
        physical_lookup_exists = True
except:
    pass

output = {
    "target_search_found": target_search_found,
    "target_search_data": target_search_data,
    "target_dashboard_found": target_dashboard_found,
    "target_dashboard_data": target_dashboard_data,
    "lookup_query_success": lookup_query_success,
    "lookup_count": lookup_count,
    "physical_lookup_exists": physical_lookup_exists,
    "new_searches": new_searches,
    "new_dashboards": new_dashboards
}

print(json.dumps(output))
PYEOF
)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)",
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "task_end_time": $(cat /tmp/task_end_time.txt 2>/dev/null || echo 0)
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="