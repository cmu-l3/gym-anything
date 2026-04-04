#!/bin/bash
# Export script for Mark Patient Deceased task

echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State Visuals
take_screenshot /tmp/task_final.png

# 2. Retrieve Context
PATIENT_ID=$(cat /tmp/task_patient_id.txt 2>/dev/null || echo "")
TARGET_DATE=$(cat /tmp/target_death_date.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query Database for Final State
if [ -n "$PATIENT_ID" ]; then
    # Get status and death date
    # Oscar typically stores date_of_death in YYYY-MM-DD format
    RESULT_ROW=$(oscar_query "SELECT patient_status, date_of_death, lastUpdateDate FROM demographic WHERE demographic_no='$PATIENT_ID'")
    
    # Parse result (tab separated)
    FINAL_STATUS=$(echo "$RESULT_ROW" | cut -f1)
    FINAL_DEATH_DATE=$(echo "$RESULT_ROW" | cut -f2)
    LAST_UPDATE=$(echo "$RESULT_ROW" | cut -f3)
    
    # Check if record was updated during task
    # (Simple check: is lastUpdateDate > task start time? Note: SQL date format vs unix timestamp requires conversion, 
    # but we can also just rely on value changes)
    # Let's convert SQL datetime to timestamp for comparison if needed, or rely on verifier logic.
else
    FINAL_STATUS="UNKNOWN"
    FINAL_DEATH_DATE="NULL"
fi

# 4. Construct JSON Result
# Using a temp file to ensure atomic write and correct permissions
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "patient_id": "$PATIENT_ID",
    "target_date_of_death": "$TARGET_DATE",
    "final_status": "$FINAL_STATUS",
    "final_date_of_death": "$FINAL_DEATH_DATE",
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save to Final Location
# Handle permissions to ensure verifier (host) can read it via copy_from_env
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Exported Data:"
cat /tmp/task_result.json
echo "=== Export Complete ==="