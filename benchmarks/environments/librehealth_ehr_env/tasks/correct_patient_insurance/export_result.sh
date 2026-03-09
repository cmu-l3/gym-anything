#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_PID=$(cat /tmp/target_pid.txt 2>/dev/null || echo "0")
INITIAL_INS_ID=$(cat /tmp/initial_insurance_id.txt 2>/dev/null || echo "0")

# Fetch current state of the primary insurance record
# We fetch specific fields: policy_number, copay, and the ID
# Note: Copay might be stored as decimal, we'll handle formatting in python
RAW_DATA=$(librehealth_query "SELECT policy_number, copay, id FROM insurance_data WHERE pid='$TARGET_PID' AND type='primary' LIMIT 1")

# Parse the raw output (tab separated)
# Expected format: "XJ9942010	25.00	123"
CURRENT_POLICY=$(echo "$RAW_DATA" | awk '{print $1}')
CURRENT_COPAY=$(echo "$RAW_DATA" | awk '{print $2}')
CURRENT_ID=$(echo "$RAW_DATA" | awk '{print $3}')

# Check if app is running
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    APP_RUNNING="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_pid": "$TARGET_PID",
    "initial_insurance_id": "$INITIAL_INS_ID",
    "final_insurance_id": "$CURRENT_ID",
    "final_policy_number": "$CURRENT_POLICY",
    "final_copay": "$CURRENT_COPAY",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="