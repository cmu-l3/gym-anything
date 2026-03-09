#!/bin/bash
# Export script for Create Appointment Type task
# Queries the database for the created appointment type

echo "=== Exporting Create Appointment Type Result ==="

source /workspace/scripts/task_utils.sh

# 1. Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Take final screenshot
take_screenshot /tmp/task_final_state.png

# 3. Query the database for the appointment type
# We select type, duration, and color. 
# Note: Color might be stored as hex or name depending on how the agent enters it.
echo "Querying database for 'Mental Health Intake'..."

DB_RESULT=$(oscar_query "SELECT type, duration, color FROM appointment_type WHERE type='Mental Health Intake' LIMIT 1" 2>/dev/null)

FOUND="false"
TYPE_NAME=""
DURATION=""
COLOR=""

if [ -n "$DB_RESULT" ]; then
    FOUND="true"
    # Parse tab-separated output
    TYPE_NAME=$(echo "$DB_RESULT" | cut -f1)
    DURATION=$(echo "$DB_RESULT" | cut -f2)
    COLOR=$(echo "$DB_RESULT" | cut -f3)
    echo "Found record: Name='$TYPE_NAME', Duration='$DURATION', Color='$COLOR'"
else
    echo "Record 'Mental Health Intake' NOT found."
fi

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "record_found": $FOUND,
    "record": {
        "name": "$TYPE_NAME",
        "duration": "$DURATION",
        "color": "$COLOR"
    },
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# 5. Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="