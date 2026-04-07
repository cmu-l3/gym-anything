#!/bin/bash
echo "=== Exporting hunt_anomalous_uri_lengths result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current saved searches
echo "Checking saved searches..."
SAVED_SEARCHES_TEMP=$(mktemp /tmp/saved_searches.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches?output_mode=json&count=0" \
    > "$SAVED_SEARCHES_TEMP" 2>/dev/null

# Extract the newly created report and its SPL pipeline
ANALYSIS=$(python3 - "$SAVED_SEARCHES_TEMP" << 'PYEOF'
import sys, json

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    entries = data.get('entry', [])

    try:
        with open('/tmp/initial_saved_searches.json', 'r') as f:
            initial_names = json.loads(f.read())
    except:
        initial_names = []

    found_report = False
    report_search = ""
    report_name = ""
    new_searches = []

    for entry in entries:
        name = entry.get('name', '')
        if name not in initial_names:
            content = entry.get('content', {})
            new_searches.append({
                "name": name,
                "search": content.get('search', '')
            })
            
            norm_name = name.lower().replace(" ", "_").replace("-", "_")
            if norm_name == "uri_length_anomaly_hunt":
                found_report = True
                report_search = content.get('search', '')
                report_name = name

    # Fallback: Evaluate logic on the first new search found if name is not an exact match
    if not found_report and len(new_searches) > 0:
        report_search = new_searches[0]["search"]
        report_name = new_searches[0]["name"]

    result = {
        "found_report": found_report,
        "report_name": report_name,
        "report_search": report_search,
        "new_searches": new_searches
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({
        "found_report": False,
        "report_name": "",
        "report_search": "",
        "new_searches": [],
        "error": str(e)
    }))
PYEOF
)
rm -f "$SAVED_SEARCHES_TEMP"

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="