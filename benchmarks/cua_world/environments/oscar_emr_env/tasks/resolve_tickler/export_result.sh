#!/bin/bash
# Export script for Resolve Tickler task
# Queries the database for the specific tickler's final state

echo "=== Exporting Resolve Tickler Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Retrieve the target tickler ID
if [ -f /tmp/target_tickler_id.txt ]; then
    TICKLER_ID=$(cat /tmp/target_tickler_id.txt)
else
    echo "ERROR: Target tickler ID not found."
    TICKLER_ID=""
fi

# 3. Query the database for this specific tickler
if [ -n "$TICKLER_ID" ]; then
    # Get the raw row data
    # Select specific fields: status, message, priority, active flag (if applicable)
    # Note: Oscar schema varies, but usually 'status' is the key field ('A'ctive, 'C'omplete)
    TICKLER_DATA=$(oscar_query "SELECT status, message, priority, update_date FROM tickler WHERE tickler_no='$TICKLER_ID'")
    
    # Check if record exists
    if [ -n "$TICKLER_DATA" ]; then
        EXISTS="true"
        STATUS=$(echo "$TICKLER_DATA" | cut -f1)
        MESSAGE=$(echo "$TICKLER_DATA" | cut -f2)
        PRIORITY=$(echo "$TICKLER_DATA" | cut -f3)
        UPDATE_DATE=$(echo "$TICKLER_DATA" | cut -f4)
    else
        EXISTS="false"
        STATUS=""
        MESSAGE=""
        PRIORITY=""
        UPDATE_DATE=""
    fi
else
    EXISTS="false"
fi

# 4. Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 5. Create JSON result
# Use python to escape the message string properly for JSON
TEMP_JSON=$(mktemp /tmp/tickler_result.XXXXXX.json)
python3 -c "
import json
import sys

data = {
    'tickler_id': '$TICKLER_ID',
    'exists': $EXISTS,
    'status': '$STATUS',
    'message': '''$MESSAGE''', 
    'update_date': '$UPDATE_DATE',
    'task_start_ts': $TASK_START,
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(data, indent=2))
" > "$TEMP_JSON"

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="