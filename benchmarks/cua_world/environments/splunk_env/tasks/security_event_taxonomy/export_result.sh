#!/bin/bash
echo "=== Exporting security_event_taxonomy result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query Splunk REST API using Python to cleanly format the result
echo "Gathering REST API configurations..."
ANALYSIS_JSON=$(python3 - << 'PYEOF'
import sys, json, subprocess

def get_json(url):
    res = subprocess.run(['curl', '-sk', '-u', 'admin:SplunkAdmin1!', url], capture_output=True, text=True)
    try:
        return json.loads(res.stdout)
    except:
        return None

# Fetch eventtypes
et_urls = {
    "ssh_brute_force": "https://localhost:8089/servicesNS/-/-/saved/eventtypes/ssh_brute_force?output_mode=json",
    "ssh_successful_login": "https://localhost:8089/servicesNS/-/-/saved/eventtypes/ssh_successful_login?output_mode=json",
    "system_error": "https://localhost:8089/servicesNS/-/-/saved/eventtypes/system_error?output_mode=json"
}
eventtypes = {}
for name, url in et_urls.items():
    data = get_json(url)
    if data and data.get('entry'):
        eventtypes[name] = data['entry'][0].get('content', {})

# Fetch tags configurations
tags_conf = get_json("https://localhost:8089/servicesNS/-/-/configs/conf-tags?output_mode=json&count=0")
tags_data = {}
if tags_conf and tags_conf.get('entry'):
    for entry in tags_conf['entry']:
        tags_data[entry['name']] = entry.get('content', {})

# Fetch saved search
ss_data = get_json("https://localhost:8089/servicesNS/-/-/saved/searches/Tagged_Security_Summary?output_mode=json")
saved_search = {}
if ss_data and ss_data.get('entry'):
    saved_search = ss_data['entry'][0].get('content', {})
else:
    # Try case-insensitive fallback
    all_ss = get_json("https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0")
    if all_ss and all_ss.get('entry'):
        for entry in all_ss['entry']:
            if entry.get('name', '').lower().replace(' ', '_') == 'tagged_security_summary':
                saved_search = entry.get('content', {})
                break

output = {
    "eventtypes": eventtypes,
    "tags_conf": tags_data,
    "saved_search": saved_search
}
print(json.dumps(output))
PYEOF
)

# Create final result file
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_eventtype_count.txt 2>/dev/null || echo "0")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "initial_eventtype_count": $INITIAL_COUNT,
    "analysis": $ANALYSIS_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="