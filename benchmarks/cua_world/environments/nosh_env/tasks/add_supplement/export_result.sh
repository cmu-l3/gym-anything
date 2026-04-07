#!/bin/bash
set -e
echo "=== Exporting add_supplement results ==="

# Load context from setup
TARGET_PID=$(cat /tmp/target_pid.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_SUP_COUNT=$(cat /tmp/initial_sup_count.txt 2>/dev/null || echo "0")

if [ -z "$TARGET_PID" ]; then
    echo "ERROR: Target PID not found"
    TARGET_PID="0"
fi

# Query current state from database
CURRENT_SUP_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT COUNT(*) FROM sup_list WHERE pid = $TARGET_PID;" 2>/dev/null || echo "0")

# Get details of the most recently added supplement for this patient
# We use JSON_OBJECT if available (MariaDB 10.2+), otherwise we construct it manually or just select fields
# Since we might be on older MySQL/MariaDB, we'll select raw fields and format in Python/Bash if needed.
# Here we'll select fields separated by a delimiter needed for JSON construction.

LATEST_SUP_DATA=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT CONCAT_WS('|', sup_supplement, sup_dosage, sup_reason, sup_instructions, UNIX_TIMESTAMP(COALESCE(created_at, updated_at))) 
     FROM sup_list 
     WHERE pid = $TARGET_PID 
     ORDER BY sup_id DESC LIMIT 1;" 2>/dev/null || echo "")

SUP_NAME=$(echo "$LATEST_SUP_DATA" | cut -d'|' -f1)
SUP_DOSAGE=$(echo "$LATEST_SUP_DATA" | cut -d'|' -f2)
SUP_REASON=$(echo "$LATEST_SUP_DATA" | cut -d'|' -f3)
SUP_INSTRUCTIONS=$(echo "$LATEST_SUP_DATA" | cut -d'|' -f4)
SUP_TIMESTAMP=$(echo "$LATEST_SUP_DATA" | cut -d'|' -f5)

# Check if app is running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Construct JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "target_pid": $TARGET_PID,
    "initial_count": $INITIAL_SUP_COUNT,
    "current_count": $CURRENT_SUP_COUNT,
    "latest_record": {
        "name": "$(echo "$SUP_NAME" | sed 's/"/\\"/g')",
        "dosage": "$(echo "$SUP_DOSAGE" | sed 's/"/\\"/g')",
        "reason": "$(echo "$SUP_REASON" | sed 's/"/\\"/g')",
        "instructions": "$(echo "$SUP_INSTRUCTIONS" | sed 's/"/\\"/g')",
        "timestamp": "${SUP_TIMESTAMP:-0}"
    },
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json