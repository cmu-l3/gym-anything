#!/bin/bash
echo "=== Exporting automated_ip_blocklist_population result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for visual evidence
take_screenshot /tmp/task_end_screenshot.png

# 1. Check if the lookup file exists and get row count via REST search
echo "Querying lookup file state..."
LOOKUP_COUNT_RAW=$(splunk_search "| inputlookup auto_blocklist.csv | stats count" "json" 2>/dev/null)
LOOKUP_COUNT=$(echo "$LOOKUP_COUNT_RAW" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    res = data.get('results', [])
    if res:
        print(res[0].get('count', '0'))
    else:
        print('0')
except:
    print('0')
" 2>/dev/null || echo "0")
echo "Lookup records found: $LOOKUP_COUNT"

# 2. Get all saved searches from the REST API
echo "Querying saved searches..."
SS_TEMP=$(mktemp /tmp/ss.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches?output_mode=json&count=0" > "$SS_TEMP" 2>/dev/null

# 3. Analyze the saved searches for the specific alert and report
ANALYSIS=$(python3 - "$SS_TEMP" << 'PYEOF'
import sys, json, re

def normalize_name(name):
    """Normalize object name for comparison."""
    return name.lower().replace(' ', '_').replace('-', '_')

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    entries = data.get('entry', [])

    alert_found = False
    alert_data = {}
    report_found = False
    report_data = {}

    # Expected names (normalized)
    expected_alert = "populate_blocklist_alert"
    expected_report = "blocklist_web_activity_report"

    for entry in entries:
        name = entry.get('name', '')
        norm_name = normalize_name(name)
        content = entry.get('content', {})

        if norm_name == expected_alert:
            alert_found = True
            alert_data = {
                "name": name,
                "search": content.get('search', ''),
                "is_scheduled": content.get('is_scheduled', '0') == '1',
                "cron_schedule": content.get('cron_schedule', '')
            }

        if norm_name == expected_report:
            report_found = True
            report_data = {
                "name": name,
                "search": content.get('search', '')
            }

    print(json.dumps({
        "alert_found": alert_found,
        "alert_data": alert_data,
        "report_found": report_found,
        "report_data": report_data
    }))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
)
rm -f "$SS_TEMP"

# 4. Construct the final JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "lookup_count": ${LOOKUP_COUNT},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

# Safely copy to destination with correct permissions
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="