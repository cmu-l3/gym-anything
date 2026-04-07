#!/bin/bash
echo "=== Exporting update_study_parameters result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Load start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
AUDIT_BASELINE=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# Get current parameters for the target study
STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1" 2>/dev/null || echo "")

COLLECT_DOB=""
GENDER_REQ=""
PERSON_ID_REQ=""
INTERVIEWER_NAME_REQ=""
INTERVIEW_DATE_REQ=""
DATE_UPDATED="0"
STUDY_EXISTS="false"

if [ -n "$STUDY_ID" ]; then
    STUDY_EXISTS="true"
    
    # Query all required fields
    PARAM_ROW=$(oc_query "SELECT collect_dob, gender_required, person_id_shown_on_crf, interviewer_name_required, interview_date_required FROM study WHERE study_id = $STUDY_ID" 2>/dev/null || echo "")
    
    COLLECT_DOB=$(echo "$PARAM_ROW" | cut -d'|' -f1)
    GENDER_REQ=$(echo "$PARAM_ROW" | cut -d'|' -f2)
    PERSON_ID_REQ=$(echo "$PARAM_ROW" | cut -d'|' -f3)
    INTERVIEWER_NAME_REQ=$(echo "$PARAM_ROW" | cut -d'|' -f4)
    INTERVIEW_DATE_REQ=$(echo "$PARAM_ROW" | cut -d'|' -f5)
    
    # Try to get update timestamp explicitly
    DATE_UPDATED=$(oc_query "SELECT EXTRACT(EPOCH FROM date_updated)::bigint FROM study WHERE study_id = $STUDY_ID" 2>/dev/null || echo "0")
    if [ -z "$DATE_UPDATED" ]; then
        DATE_UPDATED="0"
    fi
fi

# Get current audit log count
CURRENT_AUDIT=$(get_recent_audit_count 60 2>/dev/null || echo "0")

# Write out JSON
TEMP_JSON=$(mktemp /tmp/update_params_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "study_exists": $STUDY_EXISTS,
    "collect_dob": "$(json_escape "$COLLECT_DOB")",
    "gender_required": "$(json_escape "$GENDER_REQ")",
    "person_id_shown_on_crf": "$(json_escape "$PERSON_ID_REQ")",
    "interviewer_name_required": "$(json_escape "$INTERVIEWER_NAME_REQ")",
    "interview_date_required": "$(json_escape "$INTERVIEW_DATE_REQ")",
    "date_updated_epoch": $DATE_UPDATED,
    "task_start_epoch": $TASK_START,
    "audit_baseline": $AUDIT_BASELINE,
    "current_audit": $CURRENT_AUDIT,
    "result_nonce": "$NONCE"
}
EOF

# Move to final location safely
rm -f /tmp/update_params_result.json 2>/dev/null || sudo rm -f /tmp/update_params_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/update_params_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/update_params_result.json
chmod 666 /tmp/update_params_result.json 2>/dev/null || sudo chmod 666 /tmp/update_params_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete:"
cat /tmp/update_params_result.json