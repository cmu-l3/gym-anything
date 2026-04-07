#!/bin/bash
# Export: create_provider_schedule
# Queries the database for the newly created appointment block.

echo "=== Exporting task results ==="
source /workspace/scripts/task_utils.sh

# Get timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
TARGET_DATE=$(cat /tmp/target_date.txt 2>/dev/null || date -d "+1 day" +%Y-%m-%d)

echo "Target Date: $TARGET_DATE"

# Capture final screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS=$([ -f /tmp/task_final.png ] && echo "true" || echo "false")

# Query the database for the specific block
# We look for a block created AFTER task start time for the specific provider/service/date
QUERY="SELECT ab.start_datetime, ab.end_datetime, p.name, asv.name, ab.date_created 
FROM appointment_block ab 
JOIN provider prov ON ab.provider_id = prov.provider_id 
JOIN person_name p ON prov.person_id = p.person_id AND p.preferred = 1 
LEFT JOIN appointment_service asv ON ab.service_id = asv.appointment_service_id 
WHERE ab.voided = 0 
AND ab.start_datetime LIKE '$TARGET_DATE%' 
AND p.given_name = 'Super' AND p.family_name = 'User'
AND asv.name = 'General Medicine'
ORDER BY ab.appointment_block_id DESC LIMIT 1;"

# Execute Query
# Result format: 2023-10-25 09:00:00 \t 2023-10-25 17:00:00 \t Super User \t General Medicine \t 2023-10-24 10:00:00
RESULT_ROW=$(omrs_db_query "$QUERY")

FOUND="false"
START_DT=""
END_DT=""
PROVIDER=""
SERVICE=""
CREATED_DT=""
IS_NEW="false"

if [ -n "$RESULT_ROW" ]; then
    FOUND="true"
    START_DT=$(echo "$RESULT_ROW" | awk -F'\t' '{print $1}')
    END_DT=$(echo "$RESULT_ROW" | awk -F'\t' '{print $2}')
    PROVIDER=$(echo "$RESULT_ROW" | awk -F'\t' '{print $3}')
    SERVICE=$(echo "$RESULT_ROW" | awk -F'\t' '{print $4}')
    CREATED_DT=$(echo "$RESULT_ROW" | awk -F'\t' '{print $5}')
    
    # Convert created date to timestamp for anti-gaming check
    CREATED_TS=$(date -d "$CREATED_DT" +%s 2>/dev/null || echo "0")
    
    if [ "$CREATED_TS" -ge "$TASK_START" ]; then
        IS_NEW="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_date": "$TARGET_DATE",
    "block_found": $FOUND,
    "block_data": {
        "start_datetime": "$START_DT",
        "end_datetime": "$END_DT",
        "provider": "$PROVIDER",
        "service": "$SERVICE",
        "created_datetime": "$CREATED_DT"
    },
    "is_newly_created": $IS_NEW,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="