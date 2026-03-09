#!/bin/bash
echo "=== Exporting create_scheduler_task results ==="

# Source shared Bahmni task utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Function to run mysql query inside docker container
db_query() {
    local query="$1"
    docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -B -e "$query" 2>/dev/null
}

# Check if the task exists and get its details
# We select relevant columns. Using UNIX_TIMESTAMP for date_created to make JSON parsing easier
echo "Querying database for 'Hourly Alert Sync'..."
TASK_DATA=$(db_query "SELECT name, schedulable_class, repeat_interval, start_on_startup, started, UNIX_TIMESTAMP(date_created) FROM scheduler_task_config WHERE name = 'Hourly Alert Sync'")

# Parse the result
TASK_FOUND="false"
TASK_NAME=""
TASK_CLASS=""
TASK_INTERVAL=""
TASK_STARTUP=""
TASK_STARTED=""
TASK_CREATED_TS="0"

if [ -n "$TASK_DATA" ]; then
    TASK_FOUND="true"
    # Read tab-separated values
    TASK_NAME=$(echo "$TASK_DATA" | cut -f1)
    TASK_CLASS=$(echo "$TASK_DATA" | cut -f2)
    TASK_INTERVAL=$(echo "$TASK_DATA" | cut -f3)
    TASK_STARTUP=$(echo "$TASK_DATA" | cut -f4)
    TASK_STARTED=$(echo "$TASK_DATA" | cut -f5)
    TASK_CREATED_TS=$(echo "$TASK_DATA" | cut -f6)
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_found": $TASK_FOUND,
    "task_details": {
        "name": "$TASK_NAME",
        "schedulable_class": "$TASK_CLASS",
        "repeat_interval": "${TASK_INTERVAL:-0}",
        "start_on_startup": "${TASK_STARTUP:-0}",
        "started": "${TASK_STARTED:-0}",
        "date_created_ts": ${TASK_CREATED_TS:-0}
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result to /tmp/task_result.json with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="