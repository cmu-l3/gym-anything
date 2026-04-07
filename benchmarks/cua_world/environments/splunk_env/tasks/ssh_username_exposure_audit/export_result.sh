#!/bin/bash
echo "=== Exporting ssh_username_exposure_audit result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

try:
    with open('/tmp/ssh_username_exposure_initial_saved_searches.json') as f:
        initial_names = json.load(f)
except:
    initial_names = []

ss_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

found_report = False
report_name = ""
search_query = ""
new_searches = []

try:
    data = json.loads(ss_result.stdout)
    for entry in data.get('entry', []):
        name = entry.get('name', '')
        if name not in initial_names:
            new_searches.append(name)
        if name.lower() == "ssh_username_exposure_audit".lower():
            found_report = True
            report_name = name
            search_query = entry.get('content', {}).get('search', '')
except:
    pass

dynamic_results = []
execution_success = False
error_msg = ""

if search_query:
    exec_query = search_query.strip()
    if not exec_query.startswith('|') and not exec_query.lower().startswith('search'):
        exec_query = "search " + exec_query
        
    # Append head to avoid massive results
    exec_query += " | head 100"
    
    run_result = subprocess.run(
        ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
         'https://localhost:8089/services/search/jobs/export',
         '--data-urlencode', f'search={exec_query}',
         '-d', 'output_mode=json'],
        capture_output=True, text=True
    )
    
    if run_result.returncode == 0:
        for line in run_result.stdout.strip().split('\n'):
            if not line.strip(): continue
            try:
                res_obj = json.loads(line)
                if 'result' in res_obj:
                    # Filter out internal Splunk fields to emulate exact UI projection
                    clean_result = {k: v for k, v in res_obj['result'].items() if not k.startswith('__')}
                    dynamic_results.append(clean_result)
                    execution_success = True
            except:
                pass
    else:
        error_msg = run_result.stderr

output = {
    "found_report": found_report,
    "report_name": report_name,
    "search_query": search_query,
    "new_searches": new_searches,
    "execution_success": execution_success,
    "returned_events": len(dynamic_results),
    "sample_events": dynamic_results[:5],
    "error_msg": error_msg
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

safe_write_json "$TEMP_JSON" /tmp/ssh_username_exposure_result.json
echo "Result saved to /tmp/ssh_username_exposure_result.json"
echo "=== Export complete ==="