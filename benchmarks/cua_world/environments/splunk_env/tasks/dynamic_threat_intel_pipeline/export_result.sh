#!/bin/bash
echo "=== Exporting dynamic_threat_intel_pipeline result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Fetch current saved searches
SEARCHES_JSON=$(mktemp /tmp/searches.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches?output_mode=json&count=0" > "$SEARCHES_JSON" 2>/dev/null

ANALYSIS=$(python3 - "$SEARCHES_JSON" << 'PYEOF'
import sys, json

try:
    with open('/tmp/initial_saved_searches.json', 'r') as f:
        initial_names = json.load(f)
except:
    initial_names = []

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    entries = data.get('entry', [])
except:
    entries = []

new_searches = []
for entry in entries:
    name = entry.get('name', '')
    if name not in initial_names:
        content = entry.get('content', {})
        new_searches.append({
            "name": name,
            "search": content.get('search', ''),
            "is_scheduled": content.get('is_scheduled', '0') == '1' or content.get('cron_schedule', '') != '',
            "cron_schedule": content.get('cron_schedule', '')
        })

print(json.dumps({"new_searches": new_searches}))
PYEOF
)
rm -f "$SEARCHES_JSON"

# Check if the lookup file actually got created physically (extra signal, optional)
LOOKUP_EXISTS="false"
if [ -f "/opt/splunk/etc/apps/search/lookups/local_threat_intel.csv" ] || [ -f "/opt/splunk/etc/system/local/lookups/local_threat_intel.csv" ]; then
    LOOKUP_EXISTS="true"
fi

# Build final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "analysis": ${ANALYSIS},
    "lookup_file_exists": ${LOOKUP_EXISTS},
    "export_timestamp": "$(date +%s)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/pipeline_result.json

echo "Result saved to /tmp/pipeline_result.json"
cat /tmp/pipeline_result.json
echo "=== Export complete ==="