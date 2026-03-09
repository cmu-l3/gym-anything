#!/bin/bash
echo "=== Exporting Correct Diagnosis Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PATIENT_ID=$(cat /tmp/patient_id.txt 2>/dev/null || get_patient_id "Maria" "Garcia")
INITIAL_DX_ID=$(cat /tmp/initial_dx_id.txt 2>/dev/null || echo "0")

echo "Checking records for Patient ID: $PATIENT_ID"

# 1. Check for Target Diagnosis (Secondary Hypertension - 405)
# We look for active records ('A') with code 405 OR description containing "Secondary Hypertension"
TARGET_DATA=$(oscar_query "SELECT id, dx_research_code, diagnosis_desc, status, update_date FROM dxresearch WHERE demographic_no='$PATIENT_ID' AND status='A' AND (dx_research_code='405' OR diagnosis_desc LIKE '%Secondary Hypertension%') LIMIT 1")

TARGET_FOUND="false"
TARGET_ID=""
TARGET_CODE=""
TARGET_DESC=""

if [ -n "$TARGET_DATA" ]; then
    TARGET_FOUND="true"
    TARGET_ID=$(echo "$TARGET_DATA" | cut -f1)
    TARGET_CODE=$(echo "$TARGET_DATA" | cut -f2)
    TARGET_DESC=$(echo "$TARGET_DATA" | cut -f3)
    echo "Found Target Diagnosis: $TARGET_DESC ($TARGET_CODE)"
else
    echo "Target Diagnosis NOT found active."
fi

# 2. Check status of the Original Diagnosis (Essential Hypertension - 401)
# We check if the specific row ID we planted is still there and active, or if any 401 exists
ORIGINAL_DATA=$(oscar_query "SELECT id, status, dx_research_code FROM dxresearch WHERE id='$INITIAL_DX_ID'")
ORIGINAL_STATUS=""
if [ -n "$ORIGINAL_DATA" ]; then
    ORIGINAL_STATUS=$(echo "$ORIGINAL_DATA" | cut -f2)
    echo "Original Record (ID $INITIAL_DX_ID) Status: $ORIGINAL_STATUS"
else
    ORIGINAL_STATUS="DELETED"
    echo "Original Record (ID $INITIAL_DX_ID) was deleted."
fi

# Check if ANY active 401 exists (in case they added a new duplicate instead of fixing)
ANY_OLD_ACTIVE=$(oscar_query "SELECT COUNT(*) FROM dxresearch WHERE demographic_no='$PATIENT_ID' AND status='A' AND dx_research_code='401'")
echo "Count of active 401 records: $ANY_OLD_ACTIVE"

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "patient_id": "$PATIENT_ID",
    "initial_dx_id": "$INITIAL_DX_ID",
    "target_found": $TARGET_FOUND,
    "target_id": "$TARGET_ID",
    "target_code": "$TARGET_CODE",
    "target_desc": "$TARGET_DESC",
    "original_dx_status": "$ORIGINAL_STATUS",
    "active_old_diagnosis_count": ${ANY_OLD_ACTIVE:-0},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="