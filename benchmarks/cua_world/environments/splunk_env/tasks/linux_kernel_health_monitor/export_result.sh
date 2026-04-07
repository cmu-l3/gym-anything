#!/bin/bash
echo "=== Exporting linux_kernel_health_monitor result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Extract configurations via Splunk REST API using Python
echo "Extracting event types, tags, and dashboards..."

ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

def get_json(endpoint):
    res = subprocess.run(
        ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', f'https://localhost:8089{endpoint}'],
        capture_output=True, text=True
    )
    try:
        return json.loads(res.stdout)
    except:
        return {}

# 1. Fetch Event Types
eventtypes_data = get_json('/services/saved/eventtypes?output_mode=json&count=0').get('entry', [])
et_dict = {}
for et in eventtypes_data:
    name = et.get('name', '')
    search = et.get('content', {}).get('search', '')
    et_dict[name] = {
        "search": search,
        "tags": []
    }

# 2. Fetch Tags applied to Event Types
tags_data = get_json('/services/configs/conf-tags?output_mode=json&count=0').get('entry', [])
for tag_entry in tags_data:
    stanza = tag_entry.get('name', '')
    # Check if stanza is for an eventtype, e.g., 'eventtype=linux_oom_event'
    if stanza.startswith('eventtype='):
        et_name = stanza.split('=', 1)[1]
        content = tag_entry.get('content', {})
        # Active tags are keys where value is 'enabled'
        active_tags = [k for k, v in content.items() if str(v).lower() in ['enabled', '1', 'true']]
        if et_name in et_dict:
            et_dict[et_name]['tags'].extend(active_tags)

# 3. Fetch the specific dashboard
dash_data = get_json('/servicesNS/-/-/data/ui/views/Linux_Kernel_Health?output_mode=json').get('entry', [])
dash_xml = ""
if dash_data:
    dash_xml = dash_data[0].get('content', {}).get('eai:data', '')

result = {
    "eventtypes": et_dict,
    "dashboard_xml": dash_xml
}
print(json.dumps(result))
PYEOF
)

# Record task end state
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Create final JSON output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "analysis": $ANALYSIS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="