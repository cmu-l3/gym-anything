#!/bin/bash
# Export: retire_provider task
# Checks the final status of the provider via REST API and exports verification data.

echo "=== Exporting retire_provider results ==="
source /workspace/scripts/task_utils.sh

# Get Task Metadata
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PROVIDER_UUID=$(cat /tmp/task_provider_uuid 2>/dev/null || echo "")

echo "Checking status for Provider UUID: $PROVIDER_UUID"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Provider Status
PROVIDER_JSON=$(omrs_get "/provider/$PROVIDER_UUID?v=full")

# Extract details using Python
read -r RETIRED RETIRE_REASON RETIRED_BY DATE_RETIRED <<< $(echo "$PROVIDER_JSON" | python3 -c "
import sys, json, dateutil.parser

try:
    data = json.load(sys.stdin)
    retired = str(data.get('retired', False)).lower()
    reason = data.get('retireReason', '') or ''
    
    # Get audit info
    audit = data.get('auditInfo', {})
    retired_by = (audit.get('retiredBy', {}) or {}).get('display', '') or ''
    date_retired_str = audit.get('dateRetired', '') or ''
    
    # Convert date to timestamp for comparison
    date_retired_ts = 0
    if date_retired_str:
        # Handles ISO 8601 format
        import datetime
        dt = dateutil.parser.parse(date_retired_str)
        date_retired_ts = int(dt.timestamp())

    print(f'{retired} {reason.replace(\" \", \"_\")} {retired_by.replace(\" \", \"_\")} {date_retired_ts}')
except Exception as e:
    print('false error error 0')
")

# Revert underscores in reason for easier reading in JSON
RETIRE_REASON_CLEAN=$(echo "$RETIRE_REASON" | tr '_' ' ')

# Valid Timestamp Check
# We give a 10s buffer in case of slight clock skew between container/app, though usually same clock.
TIMESTAMP_VALID="false"
if [ "$DATE_RETIRED" -gt "$TASK_START" ]; then
    TIMESTAMP_VALID="true"
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "provider_uuid": "$PROVIDER_UUID",
    "is_retired": $RETIRED,
    "retire_reason": "$RETIRE_REASON_CLEAN",
    "date_retired_timestamp": $DATE_RETIRED,
    "timestamp_valid": $TIMESTAMP_VALID,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permission fix
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="