#!/bin/bash
# Export script for Restricted Data Entry Role Setup task

echo "=== Exporting Restricted Role Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")
TARGET_ROLE="Clerk - Entry Only"

echo "Querying for role: $TARGET_ROLE"

# Fetch role details including authorities
# authorities field returns a list of authority strings
ROLE_JSON=$(dhis2_api "userRoles?filter=name:eq:$TARGET_ROLE&fields=id,name,created,authorities&paging=false" 2>/dev/null)

echo "Raw API Response:"
echo "$ROLE_JSON"

# Parse result with Python
PARSED_RESULT=$(echo "$ROLE_JSON" | python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    roles = data.get('userRoles', [])
    
    if not roles:
        result = {
            'role_found': False,
            'authorities': []
        }
    else:
        role = roles[0]
        result = {
            'role_found': True,
            'id': role.get('id'),
            'name': role.get('name'),
            'created': role.get('created'),
            'authorities': role.get('authorities', [])
        }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'role_found': False, 'error': str(e)}))
" 2>/dev/null)

# Save to file
cat > /tmp/task_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "export_timestamp": "$(date -Iseconds)",
    "role_data": $PARSED_RESULT
}
ENDJSON

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="