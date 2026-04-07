#!/bin/bash
echo "=== Exporting cim_event_tagging result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve configuration data from Splunk REST API
echo "Querying Splunk REST API for Event Types, Tags, and Saved Searches..."

curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/eventtypes?output_mode=json&count=0" \
    > /tmp/et_raw.json 2>/dev/null

curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/configs/conf-tags?output_mode=json&count=0" \
    > /tmp/tags_raw.json 2>/dev/null

curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches?output_mode=json&count=0" \
    > /tmp/ss_raw.json 2>/dev/null

# Merge into a single JSON using Python
MERGE_SCRIPT=$(cat << 'PYEOF'
import json, sys, os

def load_entries(path):
    try:
        if os.path.exists(path):
            with open(path, 'r') as f:
                data = json.load(f)
                return data.get('entry', [])
    except Exception as e:
        print(f"Error loading {path}: {e}", file=sys.stderr)
    return []

eventtypes = load_entries('/tmp/et_raw.json')
tags = load_entries('/tmp/tags_raw.json')
searches = load_entries('/tmp/ss_raw.json')

result = {
    "eventtypes": eventtypes,
    "tags": tags,
    "saved_searches": searches,
    "export_timestamp": "%s"
}

with open('/tmp/cim_event_tagging_result_temp.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF
)

# Insert the timestamp into the python script safely
TIMESTAMP=$(date -Iseconds)
MERGE_SCRIPT_HYDRATED=${MERGE_SCRIPT/"%s"/$TIMESTAMP}

python3 -c "$MERGE_SCRIPT_HYDRATED"

# Move file safely
safe_write_json /tmp/cim_event_tagging_result_temp.json /tmp/cim_event_tagging_result.json

# Cleanup
rm -f /tmp/et_raw.json /tmp/tags_raw.json /tmp/ss_raw.json

echo "Result saved to /tmp/cim_event_tagging_result.json"
echo "=== Export complete ==="