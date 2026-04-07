#!/bin/bash
# Export: modify_provider_schedule
# Queries the database/API for the final state of the appointment block.

echo "=== Exporting modify_provider_schedule results ==="
source /workspace/scripts/task_utils.sh

# 1. Get Task Context
BLOCK_UUID=$(cat /tmp/target_block_uuid 2>/dev/null || echo "")
TARGET_DATE=$(cat /tmp/target_date 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Checking Block UUID: $BLOCK_UUID"

# 2. Query Block Status via REST API
# We fetch the specific block to see its current start/end times
BLOCK_JSON=$(omrs_get "/appointmentscheduling/appointmentblock/$BLOCK_UUID?v=full")

# Extract details using Python
eval $(echo "$BLOCK_JSON" | python3 -c "
import sys, json, datetime

try:
    data = json.load(sys.stdin)
    if not data or 'error' in data:
        print('BLOCK_EXISTS=false')
        print('START_TIME=')
        print('END_TIME=')
        print('PROVIDER_NAME=')
    else:
        print('BLOCK_EXISTS=true')
        
        # Parse times (ISO format)
        start = data.get('startDate', '')
        end = data.get('endDate', '')
        prov = data.get('provider', {}).get('person', {}).get('display', '')
        
        print(f'START_TIME=\"{start}\"')
        print(f'END_TIME=\"{end}\"')
        print(f'PROVIDER_NAME=\"{prov}\"')
        
        # Check voided status
        voided = str(data.get('voided', False)).lower()
        print(f'IS_VOIDED={voided}')

except Exception as e:
    print('BLOCK_EXISTS=false')
    print('ERROR_MSG=\"' + str(e) + '\"')
")

echo "Block Exists: $BLOCK_EXISTS"
echo "Start: $START_TIME"
echo "End: $END_TIME"

# 3. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Construct JSON Result
# Convert timestamps to just Time strings for easier verification in python (or keep ISO)
# We'll keep ISO and let python verifier parse dates.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "block_exists": $BLOCK_EXISTS,
    "block_uuid": "$BLOCK_UUID",
    "is_voided": ${IS_VOIDED:-false},
    "final_start_iso": "$START_TIME",
    "final_end_iso": "$END_TIME",
    "provider_name": "$PROVIDER_NAME",
    "target_date": "$TARGET_DATE",
    "task_start_ts": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="