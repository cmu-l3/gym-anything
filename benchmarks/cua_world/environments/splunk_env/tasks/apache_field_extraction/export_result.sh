#!/bin/bash
echo "=== Exporting apache_field_extraction result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Run Python script to extract current state and compare with baseline
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

def run_api(endpoint):
    cmd = ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', f'https://localhost:8089{endpoint}']
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
        return json.loads(res.stdout)
    except Exception as e:
        return {}

def run_search(query):
    cmd = ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
           'https://localhost:8089/services/search/jobs',
           '-d', f'search=search {query}', '-d', 'exec_mode=oneshot', '-d', 'output_mode=json']
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
        return json.loads(res.stdout).get('results', [])
    except Exception as e:
        return []

# Load Baselines
try:
    with open('/tmp/initial_extractions.json', 'r') as f:
        init_ext = json.load(f)
        init_ext_names = [e.get('name') for e in init_ext.get('entry', [])]
except:
    init_ext_names = []

try:
    with open('/tmp/initial_searches.json', 'r') as f:
        init_srch = json.load(f)
        init_srch_names = [e.get('name') for e in init_srch.get('entry', [])]
except:
    init_srch_names = []

# Fetch Current State
curr_ext = run_api('/servicesNS/-/-/data/props/extractions?output_mode=json&count=0')
curr_srch = run_api('/servicesNS/-/-/saved/searches?output_mode=json&count=0')

new_extractions = []
for e in curr_ext.get('entry', []):
    if e.get('name') not in init_ext_names:
        new_extractions.append({
            "name": e.get('name', ''),
            "stanza": e.get('content', {}).get('stanza', ''),
            "value": e.get('content', {}).get('value', '')
        })

new_searches = []
for e in curr_srch.get('entry', []):
    if e.get('name') not in init_srch_names:
        new_searches.append({
            "name": e.get('name', ''),
            "search": e.get('content', {}).get('search', '')
        })

# Perform Functional Testing
# Validates if the extractions actually work on the real data
sev_results = run_search('index=web_logs sourcetype=apache_error | stats count by error_severity | where isnotnull(error_severity)')
ip_results = run_search('index=web_logs sourcetype=apache_error | stats count by log_client_ip | where isnotnull(log_client_ip)')

output = {
    "new_extractions": new_extractions,
    "new_searches": new_searches,
    "functional_tests": {
        "error_severity_results": len(sev_results),
        "log_client_ip_results": len(ip_results)
    }
}

print(json.dumps(output))
PYEOF
)

# Output JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/apache_field_extraction_result.json
echo "Result saved to /tmp/apache_field_extraction_result.json"
cat /tmp/apache_field_extraction_result.json
echo "=== Export complete ==="