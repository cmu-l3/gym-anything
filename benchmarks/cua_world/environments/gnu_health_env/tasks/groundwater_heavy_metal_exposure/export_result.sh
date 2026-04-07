#!/bin/bash
echo "=== Exporting groundwater_heavy_metal_exposure result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/ghme_final_state.png

# Load baselines and identifiers
BASELINE_DISEASE_MAX=$(cat /tmp/ghme_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/ghme_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/ghme_baseline_eval_max 2>/dev/null || echo "0")
JOHN_PATIENT_ID=$(cat /tmp/ghme_john_patient_id 2>/dev/null || echo "0")
MATT_PATIENT_ID=$(cat /tmp/ghme_matt_patient_id 2>/dev/null || echo "0")

echo "Target patient_ids - John: $JOHN_PATIENT_ID, Matt: $MATT_PATIENT_ID"

# -----------------------------------------------------------------------------
# Check 1: John Zenon Diagnosis (T56.x)
# -----------------------------------------------------------------------------
JOHN_T56_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $JOHN_PATIENT_ID
      AND gpath.code LIKE 'T56%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

JOHN_T56_FOUND="false"
JOHN_T56_ACTIVE="false"
JOHN_T56_CODE="null"

if [ -n "$JOHN_T56_RECORD" ]; then
    JOHN_T56_FOUND="true"
    JOHN_T56_CODE=$(echo "$JOHN_T56_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$JOHN_T56_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        JOHN_T56_ACTIVE="true"
    fi
fi

# -----------------------------------------------------------------------------
# Check 2: Matt Zenon Betz Diagnosis (T56.x)
# -----------------------------------------------------------------------------
MATT_T56_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $MATT_PATIENT_ID
      AND gpath.code LIKE 'T56%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

MATT_T56_FOUND="false"
MATT_T56_ACTIVE="false"
MATT_T56_CODE="null"

if [ -n "$MATT_T56_RECORD" ]; then
    MATT_T56_FOUND="true"
    MATT_T56_CODE=$(echo "$MATT_T56_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$MATT_T56_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        MATT_T56_ACTIVE="true"
    fi
fi

# -----------------------------------------------------------------------------
# Check 3 & 4: Lab orders for John and Matt
# -----------------------------------------------------------------------------
JOHN_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $JOHN_PATIENT_ID
      AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')

MATT_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $MATT_PATIENT_ID
      AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')

# -----------------------------------------------------------------------------
# Check 5: Incident Documentation for John
# -----------------------------------------------------------------------------
# We'll extract chief_complaint, present_illness, and notes fields to safely check content via python later
EVAL_TEXT_JOHN_RAW=$(gnuhealth_db_query "
    SELECT COALESCE(chief_complaint, '') || ' | ' || COALESCE(present_illness, '')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $JOHN_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Escape to JSON safely using Python
EVAL_TEXT_JOHN_JSON=$(python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))" <<< "$EVAL_TEXT_JOHN_RAW")

# Check if ANY evaluation exists for John to award partial credit
EVAL_EXISTS_JOHN="false"
EVAL_COUNT_JOHN=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient_evaluation WHERE patient = $JOHN_PATIENT_ID AND id > $BASELINE_EVAL_MAX" | tr -d '[:space:]')
if [ "${EVAL_COUNT_JOHN:-0}" -gt 0 ]; then
    EVAL_EXISTS_JOHN="true"
fi

# -----------------------------------------------------------------------------
# Write JSON result file
# -----------------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "john_patient_id": $JOHN_PATIENT_ID,
    "matt_patient_id": $MATT_PATIENT_ID,
    "john_t56_found": $JOHN_T56_FOUND,
    "john_t56_active": $JOHN_T56_ACTIVE,
    "john_t56_code": "$JOHN_T56_CODE",
    "matt_t56_found": $MATT_T56_FOUND,
    "matt_t56_active": $MATT_T56_ACTIVE,
    "matt_t56_code": "$MATT_T56_CODE",
    "john_lab_count": ${JOHN_LAB_COUNT:-0},
    "matt_lab_count": ${MATT_LAB_COUNT:-0},
    "john_eval_exists": $EVAL_EXISTS_JOHN,
    "john_eval_text": $EVAL_TEXT_JOHN_JSON
}
EOF

rm -f /tmp/groundwater_heavy_metal_exposure_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/groundwater_heavy_metal_exposure_result.json
chmod 666 /tmp/groundwater_heavy_metal_exposure_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/groundwater_heavy_metal_exposure_result.json
echo "=== Export complete ==="