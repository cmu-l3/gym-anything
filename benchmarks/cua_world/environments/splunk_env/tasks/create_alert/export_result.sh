#!/bin/bash
echo "=== Exporting create_alert result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current saved searches
echo "Checking saved searches..."
SAVED_SEARCHES_TEMP=$(mktemp /tmp/saved_searches.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches?output_mode=json&count=0" \
    > "$SAVED_SEARCHES_TEMP" 2>/dev/null

# Analyze saved searches for the expected alert
# STRICT: Must match verifier requirements exactly
# - Alert name must be "Brute_Force_Detection" (normalized)
# - Search must contain "security_logs" AND "failed"
# - Cron must be "*/5 * * * *"
ALERT_ANALYSIS=$(python3 - "$SAVED_SEARCHES_TEMP" << 'PYEOF'
import sys, json

def normalize_name(name):
    """Normalize alert name for comparison."""
    return name.lower().replace(' ', '_').replace('-', '_')

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    entries = data.get('entry', [])

    # Load initial saved searches
    try:
        with open('/tmp/initial_saved_searches.json', 'r') as f:
            initial_names = json.loads(f.read())
    except:
        initial_names = []

    found_alert = False
    alert_name = ""
    alert_search = ""
    is_scheduled = False
    cron_schedule = ""
    alert_type = ""
    alert_actions = ""
    all_current_names = []
    new_saved_searches = []

    # Expected name (normalized)
    expected_name_normalized = "brute_force_detection"

    for entry in entries:
        name = entry.get('name', '')
        all_current_names.append(name)
        content = entry.get('content', {})

        if name not in initial_names:
            new_saved_searches.append(name)

        # STRICT: Check for exact name match "Brute_Force_Detection" (normalized)
        name_normalized = normalize_name(name)
        is_exact_name_match = (name_normalized == expected_name_normalized)

        search_text = content.get('search', '').lower()

        # STRICT: Search must contain both "security_logs" AND "failed"
        has_security_logs = 'security_logs' in search_text
        has_failed = 'failed' in search_text
        has_correct_search = has_security_logs and has_failed

        # Check if it's a scheduled alert
        is_alert = content.get('is_scheduled', '0') == '1' or \
                   content.get('cron_schedule', '') != ''

        # Only match if name is exactly "Brute_Force_Detection"
        if is_exact_name_match:
            found_alert = True
            alert_name = name
            alert_search = content.get('search', '')
            is_scheduled = content.get('is_scheduled', '0') == '1'
            cron_schedule = content.get('cron_schedule', '')
            alert_type = content.get('alert_type', '')
            alert_actions = content.get('actions', '')
            break

    # If we didn't find the exact name, check for any new alert that matches criteria
    # This fallback exports the data but the verifier will still fail if name is wrong
    if not found_alert and new_saved_searches:
        for entry in entries:
            name = entry.get('name', '')
            if name in new_saved_searches:
                content = entry.get('content', {})
                search_text = content.get('search', '').lower()
                has_security_logs = 'security_logs' in search_text
                has_failed = 'failed' in search_text

                # Report the alert but note it doesn't have the correct name
                found_alert = True
                alert_name = name
                alert_search = content.get('search', '')
                is_scheduled = content.get('is_scheduled', '0') == '1'
                cron_schedule = content.get('cron_schedule', '')
                alert_type = content.get('alert_type', '')
                alert_actions = content.get('actions', '')
                break

    result = {
        "found_alert": found_alert,
        "alert_name": alert_name,
        "alert_search": alert_search,
        "is_scheduled": is_scheduled,
        "cron_schedule": cron_schedule,
        "alert_type": alert_type,
        "alert_actions": alert_actions,
        "new_saved_searches": new_saved_searches,
        "total_saved_searches": len(all_current_names)
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({
        "found_alert": False,
        "alert_name": "",
        "alert_search": "",
        "is_scheduled": False,
        "cron_schedule": "",
        "alert_type": "",
        "alert_actions": "",
        "new_saved_searches": [],
        "total_saved_searches": 0,
        "error": str(e)
    }))
PYEOF
)
rm -f "$SAVED_SEARCHES_TEMP"

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_saved_search_count 2>/dev/null || echo "0")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "alert_analysis": ${ALERT_ANALYSIS},
    "initial_saved_search_count": ${INITIAL_COUNT},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
