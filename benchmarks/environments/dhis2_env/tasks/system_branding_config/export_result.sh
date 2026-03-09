#!/bin/bash
# Export script for System Branding Config task

echo "=== Exporting System Branding Config Result ==="

source /workspace/scripts/task_utils.sh

# Helper to get system setting
get_setting() {
    local key="$1"
    # Use -H "Accept: text/plain" to get raw value if possible, or parse JSON
    # DHIS2 systemSettings API returns the value directly for text keys if accepted content type is text/plain
    local val=$(curl -s -u admin:district -H "Accept: text/plain" "http://localhost:8080/api/systemSettings/$key")
    # If the response looks like JSON (starts with {), try to extract value, otherwise use as is
    if [[ "$val" == \{* ]]; then
        # It might be an error or complex object, try to just cat it
        echo "$val"
    else
        echo "$val"
    fi
}

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Capture timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Query current settings
echo "Querying system settings..."

TITLE=$(get_setting "applicationTitle")
INTRO=$(get_setting "applicationIntro")
NOTIF=$(get_setting "applicationNotification")
LIMIT=$(get_setting "keyAnalyticsMaxLimit")
FOOTER=$(get_setting "applicationFooter")
INFRA=$(get_setting "keyInfrastructuralIndicators")

# Create JSON result safely using python to escape strings
python3 -c "
import json
import os
import sys

try:
    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'settings': {
            'applicationTitle': '''$TITLE''',
            'applicationIntro': '''$INTRO''',
            'applicationNotification': '''$NOTIF''',
            'keyAnalyticsMaxLimit': '''$LIMIT''',
            'applicationFooter': '''$FOOTER''',
            'keyInfrastructuralIndicators': '''$INFRA'''
        }
    }
    with open('/tmp/system_branding_result.json', 'w') as f:
        json.dump(result, f, indent=2)
    print('JSON export successful')
except Exception as e:
    print(f'Error creating JSON: {e}')
"

echo ""
echo "Exported settings:"
cat /tmp/system_branding_result.json
echo ""

# Cleanup and save to final location
chmod 666 /tmp/system_branding_result.json 2>/dev/null || true
echo "=== Export Complete ==="