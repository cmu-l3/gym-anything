#!/bin/bash
echo "=== Exporting first_time_seen_ip_detection result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess, urllib.parse

try:
    with open('/tmp/initial_saved_searches.json') as f:
        initial_ss = json.load(f)
except:
    initial_ss = []

ss_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

baseline_search_data = None
alert_search_data = None

try:
    ss_data = json.loads(ss_result.stdout)
    for entry in ss_data.get('entry', []):
        name = entry.get('name', '')
        content = entry.get('content', {})
        search_query = content.get('search', '')
        
        is_valid_spl = False
        if search_query:
            # Splunk parser endpoint to validate syntax
            parse_res = subprocess.run(
                ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
                 'https://localhost:8089/services/search/parser',
                 '--data-urlencode', f'q=search {search_query}',
                 '-d', 'output_mode=json'],
                capture_output=True, text=True
            )
            try:
                parse_data = json.loads(parse_res.stdout)
                messages = parse_data.get('messages', [])
                has_error = any(m.get('type') in ['FATAL', 'ERROR'] for m in messages)
                is_valid_spl = not has_error
            except:
                pass
        
        search_obj = {
            "name": name,
            "search": search_query,
            "is_valid_spl": is_valid_spl,
            "is_new": name not in initial_ss
        }
        
        norm_name = name.lower().replace(' ', '_').replace('-', '_')
        if norm_name == "baseline_known_user_ips":
            baseline_search_data = search_obj
        elif norm_name == "first_time_seen_login_alert":
            alert_search_data = search_obj
except Exception as e:
    pass

output = {
    "baseline_report": baseline_search_data,
    "detection_alert": alert_search_data
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

safe_write_json "$TEMP_JSON" /tmp/first_time_seen_ip_detection_result.json
echo "Result saved to /tmp/first_time_seen_ip_detection_result.json"
cat /tmp/first_time_seen_ip_detection_result.json
echo "=== Export complete ==="