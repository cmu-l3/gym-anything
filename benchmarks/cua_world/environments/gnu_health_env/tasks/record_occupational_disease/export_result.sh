#!/bin/bash
echo "=== Exporting record_occupational_disease result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/occ_final_state.png ga

# Load baselines and state
TARGET_PATIENT_ID=$(cat /tmp/occ_target_patient_id 2>/dev/null || echo "0")
BASELINE_MAX_ID=$(cat /tmp/occ_baseline_max_id 2>/dev/null || echo "0")
BASELINE_COUNT=$(cat /tmp/occ_baseline_count 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/occ_task_start_time 2>/dev/null || echo "0")

echo "Target patient_id: $TARGET_PATIENT_ID"

# Check if application was running
APP_RUNNING="false"
if pgrep -f "trytond" > /dev/null; then
    APP_RUNNING="true"
fi

# Get current disease count for patient
CURRENT_COUNT=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient_disease WHERE patient = $TARGET_PATIENT_ID" | tr -d '[:space:]')

# Find the newest disease record for this patient created during the task
NEWEST_DISEASE_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_patient_disease 
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_MAX_ID 
    ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')

DISEASE_FOUND="false"
DISEASE_CODE="null"
DISEASE_DATE="null"
DISEASE_ACTIVE="false"
DISEASE_NOTES=""
CREATE_TIME_EPOCH=0

if [ -n "$NEWEST_DISEASE_ID" ]; then
    DISEASE_FOUND="true"
    
    # Extract details safely
    RECORD_DATA=$(gnuhealth_db_query "
        SELECT 
            COALESCE(gpath.code, 'unknown'),
            COALESCE(gpd.diagnosed_date::text, 'unknown'),
            gpd.is_active::text,
            EXTRACT(EPOCH FROM gpd.create_date)
        FROM gnuhealth_patient_disease gpd
        LEFT JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
        WHERE gpd.id = $NEWEST_DISEASE_ID
    " 2>/dev/null | head -1)
    
    DISEASE_CODE=$(echo "$RECORD_DATA" | awk -F'|' '{print $1}' | tr -d ' ')
    DISEASE_DATE=$(echo "$RECORD_DATA" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$RECORD_DATA" | awk -F'|' '{print $3}' | tr -d ' ')
    CREATE_TIME_EPOCH=$(echo "$RECORD_DATA" | awk -F'|' '{print $4}' | cut -d. -f1 | tr -d ' ')
    
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        DISEASE_ACTIVE="true"
    fi
    
    # Try different possible column names for notes (short_comment or extra_info)
    NOTES_RAW=$(gnuhealth_db_query "SELECT short_comment FROM gnuhealth_patient_disease WHERE id = $NEWEST_DISEASE_ID" 2>/dev/null)
    if [ -z "$NOTES_RAW" ]; then
        NOTES_RAW=$(gnuhealth_db_query "SELECT extra_info FROM gnuhealth_patient_disease WHERE id = $NEWEST_DISEASE_ID" 2>/dev/null)
    fi
    DISEASE_NOTES=$(json_escape "$NOTES_RAW")
fi

echo "Disease found: $DISEASE_FOUND (code=$DISEASE_CODE, date=$DISEASE_DATE)"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/occ_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "app_running": $APP_RUNNING,
    "target_patient_id": $TARGET_PATIENT_ID,
    "baseline_disease_count": ${BASELINE_COUNT:-0},
    "current_disease_count": ${CURRENT_COUNT:-0},
    "disease_record_found": $DISEASE_FOUND,
    "disease_code": "$DISEASE_CODE",
    "disease_date": "$DISEASE_DATE",
    "disease_active": $DISEASE_ACTIVE,
    "disease_notes": "$DISEASE_NOTES",
    "disease_create_time": ${CREATE_TIME_EPOCH:-0},
    "screenshot_path": "/tmp/occ_final_state.png"
}
EOF

safe_write_result /tmp/occupational_disease_result.json "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/occupational_disease_result.json"
cat /tmp/occupational_disease_result.json
echo "=== Export complete ==="