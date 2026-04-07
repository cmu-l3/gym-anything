#!/bin/bash
# Export Result: Correct Encounter Timestamp
# Exports the final state of the specific encounter from the database/API

set -e
echo "=== Exporting Results ==="
source /workspace/scripts/task_utils.sh

# Load context
ENC_UUID=$(cat /tmp/task_encounter_uuid.txt 2>/dev/null || echo "")
PATIENT_UUID=$(cat /tmp/task_patient_uuid.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS=$([ -f /tmp/task_final.png ] && echo "true" || echo "false")

# Query OpenMRS DB for the encounter status
# We need: encounter_datetime, date_changed (to prove edit), voided status
if [ -n "$ENC_UUID" ]; then
    # Helper to run SQL inside the DB container
    SQL_QUERY="SELECT encounter_datetime, date_changed, voided FROM encounter WHERE uuid = '$ENC_UUID';"
    DB_RESULT=$(omrs_db_query "$SQL_QUERY")
    
    # Parse result (Mariadb output is tab separated)
    # Expected format: 2025-01-15 14:00:00    2025-10-22 10:00:00    0
    FINAL_DATETIME=$(echo "$DB_RESULT" | awk '{print $1" "$2}')
    DATE_CHANGED=$(echo "$DB_RESULT" | awk '{print $3" "$4}')
    VOIDED=$(echo "$DB_RESULT" | awk '{print $5}')
else
    FINAL_DATETIME=""
    DATE_CHANGED=""
    VOIDED="1"
fi

# Convert timestamps to unix for easier comparison in python if needed, 
# or keep as string. Let's keep as string but also export raw values.

# Check if app is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "target_encounter_uuid": "$ENC_UUID",
    "patient_uuid": "$PATIENT_UUID",
    "final_encounter_datetime": "$FINAL_DATETIME",
    "date_changed_db": "$DATE_CHANGED",
    "is_voided": "$VOIDED",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Exported result to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="