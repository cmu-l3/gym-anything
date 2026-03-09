#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Gather context
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
PID=$(cat /tmp/task_pid.txt 2>/dev/null)
ADMIN_ID=$(cat /tmp/task_admin_id.txt 2>/dev/null)
INITIAL_PROVIDER_ID=$(cat /tmp/task_initial_provider_id.txt 2>/dev/null)

if [ -z "$PID" ] || [ -z "$ADMIN_ID" ]; then
    echo "ERROR: Missing setup data (PID or Admin ID)"
    # Generate a failure result
    cat > /tmp/task_result.json << EOF
{
    "error": "Setup data missing",
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF
    exit 0
fi

# 2. Query Current State from Database
# Get the current providerID for the target patient
CURRENT_PROVIDER_ID=$(librehealth_query "SELECT providerID FROM patient_data WHERE pid=${PID}")
# Handle NULL/Empty
if [ -z "$CURRENT_PROVIDER_ID" ]; then CURRENT_PROVIDER_ID="0"; fi

# 3. Capture Final Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS=$([ -f /tmp/task_final.png ] && echo "true" || echo "false")

# 4. Check if Admin was successfully assigned
# Success if current_provider_id matches admin_id
IS_ASSIGNED="false"
if [ "$CURRENT_PROVIDER_ID" == "$ADMIN_ID" ]; then
    IS_ASSIGNED="true"
fi

# 5. Check if state actually changed (Anti-gaming)
STATE_CHANGED="false"
if [ "$CURRENT_PROVIDER_ID" != "$INITIAL_PROVIDER_ID" ]; then
    STATE_CHANGED="true"
fi

# 6. Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pid": $PID,
    "admin_id": $ADMIN_ID,
    "initial_provider_id": "$INITIAL_PROVIDER_ID",
    "current_provider_id": "$CURRENT_PROVIDER_ID",
    "is_assigned": $IS_ASSIGNED,
    "state_changed": $STATE_CHANGED,
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="