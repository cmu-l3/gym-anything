#!/bin/bash
echo "=== Exporting document_workplace_fatality result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/fatality_final_state.png
sleep 1

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/fatality_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/fatality_baseline_eval_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/fatality_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/fatality_task_start_date 2>/dev/null || date +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- 1. Check Deceased Status, Date of Death, and Cause of Death ---
PATIENT_INFO=$(gnuhealth_db_query "
    SELECT COALESCE(gp.deceased::text, 'false'), 
           COALESCE(gp.dod::text, 'null'), 
           COALESCE(gpath.code, 'null')
    FROM gnuhealth_patient gp
    LEFT JOIN gnuhealth_pathology gpath ON gp.cod = gpath.id
    WHERE gp.id = $TARGET_PATIENT_ID
" 2>/dev/null | head -1)

DECEASED=$(echo "$PATIENT_INFO" | awk -F'|' '{print $1}' | tr -d ' ')
DOD=$(echo "$PATIENT_INFO" | awk -F'|' '{print $2}' | tr -d ' ')
COD=$(echo "$PATIENT_INFO" | awk -F'|' '{print $3}' | tr -d ' ')

echo "Patient deceased=$DECEASED, dod=$DOD, cod=$COD"

# --- 2. Check for new T59.x Toxic Exposure disease record ---
T59_INFO=$(gnuhealth_db_query "
    SELECT gpd.is_active::text, gpath.code
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'T59%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1
" 2>/dev/null | head -1)

T59_FOUND="false"
T59_ACTIVE="false"
T59_CODE="null"
if [ -n "$T59_INFO" ]; then
    T59_FOUND="true"
    T59_ACTIVE=$(echo "$T59_INFO" | awk -F'|' '{print $1}' | tr -d ' ')
    T59_CODE=$(echo "$T59_INFO" | awk -F'|' '{print $2}' | tr -d ' ')
fi

# --- 3. Check for new Contributing Respiratory Failure (J96/J68/J80) ---
J_INFO=$(gnuhealth_db_query "
    SELECT gpd.is_active::text, gpath.code
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'J96%' OR gpath.code LIKE 'J68%' OR gpath.code LIKE 'J80%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1
" 2>/dev/null | head -1)

J_FOUND="false"
J_CODE="null"
if [ -n "$J_INFO" ]; then
    J_FOUND="true"
    J_CODE=$(echo "$J_INFO" | awk -F'|' '{print $2}' | tr -d ' ')
fi

# --- 4. Check for new Clinical Evaluation ---
EVAL_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) 
    FROM gnuhealth_patient_evaluation 
    WHERE patient = $TARGET_PATIENT_ID 
      AND id > $BASELINE_EVAL_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- 5. Export JSON ---
TEMP_JSON=$(mktemp /tmp/fatality_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": $TARGET_PATIENT_ID,
    "patient_deceased": "$DECEASED",
    "patient_dod": "$DOD",
    "patient_cod": "$COD",
    "t59_disease_found": $T59_FOUND,
    "t59_disease_active": "$T59_ACTIVE",
    "t59_disease_code": "$T59_CODE",
    "j_disease_found": $J_FOUND,
    "j_disease_code": "$J_CODE",
    "new_eval_count": ${EVAL_COUNT:-0},
    "today_date": "$TODAY",
    "task_start_date": "$TASK_START_DATE"
}
EOF

# Move securely
rm -f /tmp/document_workplace_fatality_result.json 2>/dev/null || sudo rm -f /tmp/document_workplace_fatality_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/document_workplace_fatality_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/document_workplace_fatality_result.json
chmod 666 /tmp/document_workplace_fatality_result.json 2>/dev/null || sudo chmod 666 /tmp/document_workplace_fatality_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/document_workplace_fatality_result.json
echo "=== Export complete ==="