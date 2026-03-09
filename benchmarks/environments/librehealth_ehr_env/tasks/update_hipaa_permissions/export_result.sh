#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Target PID from setup
TARGET_PID=5

# 1. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Query Current Database State for the Target Patient
# We get the raw values for the 3 fields of interest
DB_RESULT=$(librehealth_query "SELECT hipaa_voice, hipaa_mail, hipaa_allowsms, date FROM patient_data WHERE pid=${TARGET_PID}")

# Parse the result (Tab separated: voice mail sms date)
# Note: MariaDB boolean/tinyint returns 1 or 0
CURRENT_VOICE=$(echo "$DB_RESULT" | awk '{print $1}')
CURRENT_MAIL=$(echo "$DB_RESULT" | awk '{print $2}')
CURRENT_SMS=$(echo "$DB_RESULT" | awk '{print $3}')
LAST_UPDATE=$(echo "$DB_RESULT" | awk '{$1=$2=$3=""; print $0}' | sed 's/^ *//')

# 3. Convert Last Update to Timestamp for comparison
# LibreHealth 'date' field format is typically YYYY-MM-DD HH:MM:SS
LAST_UPDATE_TS=$(date -d "$LAST_UPDATE" +%s 2>/dev/null || echo "0")

# 4. Check if Record was Modified During Task
# The setup script set the date to 2020. If it's recent, the agent touched it.
RECORD_MODIFIED="false"
if [ "$LAST_UPDATE_TS" -ge "$TASK_START" ]; then
    RECORD_MODIFIED="true"
fi

# 5. Check if App is Still Running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 6. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "record_modified_during_task": $RECORD_MODIFIED,
    "target_pid": $TARGET_PID,
    "final_voice": "$CURRENT_VOICE",
    "final_mail": "$CURRENT_MAIL",
    "final_sms": "$CURRENT_SMS",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported Data:"
cat /tmp/task_result.json
echo "=== Export Complete ==="