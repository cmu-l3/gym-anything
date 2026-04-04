#!/bin/bash
# Export script for Reassign Task

echo "=== Exporting Reassign Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Retrieve the target Tickler ID
if [ -f /tmp/target_tickler_id.txt ]; then
    TARGET_ID=$(cat /tmp/target_tickler_id.txt)
else
    TARGET_ID=""
    echo "WARNING: Target Tickler ID not found in /tmp"
fi

# Query the database for the final state of this specific tickler
if [ -n "$TARGET_ID" ]; then
    # Fetch raw fields: assigned_to, priority, status, message
    # Using specific delimiters to parse safely
    RESULT_RAW=$(oscar_query "SELECT assigned_to, priority, status, message FROM tickler WHERE tickler_no='$TARGET_ID'")
    
    # Parse results (tab separated by default in mysql -N)
    ASSIGNED_TO=$(echo "$RESULT_RAW" | awk -F'\t' '{print $1}')
    PRIORITY=$(echo "$RESULT_RAW" | awk -F'\t' '{print $2}')
    STATUS=$(echo "$RESULT_RAW" | awk -F'\t' '{print $3}')
    MESSAGE=$(echo "$RESULT_RAW" | awk -F'\t' '{print $4}')
    
    TICKLER_EXISTS="true"
else
    TICKLER_EXISTS="false"
    ASSIGNED_TO=""
    PRIORITY=""
    STATUS=""
    MESSAGE=""
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_tickler_id": "${TARGET_ID}",
    "tickler_exists": ${TICKLER_EXISTS},
    "assigned_to": "${ASSIGNED_TO}",
    "priority": "${PRIORITY}",
    "status": "${STATUS}",
    "message": "${MESSAGE}",
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="