#!/bin/bash
echo "=== Exporting session_hijacking_detection result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve current saved searches via REST API
echo "Retrieving current saved searches..."
SAVED_SEARCHES_TEMP=$(mktemp /tmp/saved_searches.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches?output_mode=json&count=0" \
    > "$SAVED_SEARCHES_TEMP" 2>/dev/null

# Analyze saved searches to find the expected alert and its properties
ANALYSIS=$(python3 - "$SAVED_SEARCHES_TEMP" << 'PYEOF'
import sys, json

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    entries = data.get('entry', [])

    try:
        with open('/tmp/session_hijack_initial_searches.json', 'r') as f:
            initial_names = json.loads(f.read())
    except:
        initial_names = []

    found_alert = False
    alert_name = ""
    alert_search = ""
    is_scheduled = False
    cron_schedule = ""
    new_searches = []
    
    expected_name_normalized = "session_hijacking_alert"

    for entry in entries:
        name = entry.get('name', '')
        content = entry.get('content', {})
        
        if name not in initial_names:
            new_searches.append(name)
            
        # Check for case-insensitive exact match
        if name.lower().replace(' ', '_').replace('-', '_') == expected_name_normalized:
            found_alert = True
            alert_name = name
            alert_search = content.get('search', '')
            is_scheduled = str(content.get('is_scheduled', '0')) == '1' or content.get('cron_schedule', '') != ''
            cron_schedule = content.get('cron_schedule', '')
            break

    # If the exact name wasn't found, fall back to checking ANY new search to provide partial credit via verifier
    if not found_alert and new_searches:
        for entry in entries:
            name = entry.get('name', '')
            if name in new_searches:
                content = entry.get('content', {})
                search_text = content.get('search', '').lower()
                
                # Loose heuristic to check if this is the attempted task
                if 'dc(' in search_text or 'distinct_count' in search_text or 'jsessionid' in search_text:
                    found_alert = True
                    alert_name = name
                    alert_search = content.get('search', '')
                    is_scheduled = str(content.get('is_scheduled', '0')) == '1' or content.get('cron_schedule', '') != ''
                    cron_schedule = content.get('cron_schedule', '')
                    break

    result = {
        "found_alert": found_alert,
        "alert_name": alert_name,
        "alert_search": alert_search,
        "is_scheduled": is_scheduled,
        "cron_schedule": cron_schedule,
        "new_searches": new_searches,
        "total_searches": len(entries)
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e), "found_alert": False}))
PYEOF
)
rm -f "$SAVED_SEARCHES_TEMP"

INITIAL_COUNT=$(cat /tmp/initial_saved_search_count 2>/dev/null || echo "0")

# Construct output JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "alert_analysis": ${ANALYSIS},
    "initial_search_count": ${INITIAL_COUNT},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="