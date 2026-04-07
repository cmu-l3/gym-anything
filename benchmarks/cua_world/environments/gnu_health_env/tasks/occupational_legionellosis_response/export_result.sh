#!/bin/bash
echo "=== Exporting occupational_legionellosis_response result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/legion_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/legion_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/legion_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/legion_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/legion_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/legion_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/legion_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/legion_task_start_date 2>/dev/null || date +%Y-%m-%d)
CURRENT_DATE=$(date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: A48.1 Legionnaires' disease diagnosis ---
A48_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'A48.1%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

A48_FOUND="false"
A48_ACTIVE="false"
A48_CODE="null"
if [ -n "$A48_RECORD" ]; then
    A48_FOUND="true"
    A48_CODE=$(echo "$A48_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$A48_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        A48_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient_disease WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Clinical evaluation with fever (>= 39.0) ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(temperature::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_TEMP="null"
EVAL_HAS_HIGH_FEVER="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_TEMP=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    if echo "$EVAL_TEMP" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        FEVER_CHECK=$(echo "$EVAL_TEMP" | awk '{if ($1 >= 39.0) print "true"; else print "false"}')
        EVAL_HAS_HIGH_FEVER="${FEVER_CHECK:-false}"
    fi
fi

# --- Check 3: Laboratory orders (>= 2) ---
NEW_LAB_COUNT=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient_lab_test WHERE patient_id = $TARGET_PATIENT_ID AND id > $BASELINE_LAB_MAX" 2>/dev/null | tr -d '[:space:]')
NEW_LAB_TYPES=$(gnuhealth_db_query "
    SELECT ltt.code FROM gnuhealth_patient_lab_test glt
    JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
    WHERE glt.patient_id = $TARGET_PATIENT_ID AND glt.id > $BASELINE_LAB_MAX
" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# --- Check 4: Antibiotic prescription (Macrolide/Fluoroquinolone) ---
PRESC_FOUND="false"
ABX_FOUND="false"
ABX_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_prescription_order WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_PRESCRIPTION_MAX ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"
    ABX_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%azithromycin%' OR LOWER(pt.name) LIKE '%levofloxacin%' OR LOWER(pt.name) LIKE '%ciprofloxacin%' OR LOWER(pt.name) LIKE '%moxifloxacin%' OR LOWER(pt.name) LIKE '%clarithromycin%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$ABX_CHECK" ]; then
        ABX_FOUND="true"
        ABX_NAME="$ABX_CHECK"
    fi
fi

# --- Check 5: Follow-up Appointment (3-7 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

APPT_FOUND="false"
APPT_DATE="none"
APPT_DAYS_DIFF="0"
APPT_IN_RANGE="false"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE="$APPT_RECORD"
    # Calculate difference in days
    START_SEC=$(date -d "$CURRENT_DATE" +%s 2>/dev/null || echo 0)
    APPT_SEC=$(date -d "$APPT_DATE" +%s 2>/dev/null || echo 0)
    if [ "$START_SEC" -gt 0 ] && [ "$APPT_SEC" -gt 0 ]; then
        DIFF_SEC=$((APPT_SEC - START_SEC))
        APPT_DAYS_DIFF=$((DIFF_SEC / 86400))
        if [ "$APPT_DAYS_DIFF" -ge 3 ] && [ "$APPT_DAYS_DIFF" -le 7 ]; then
            APPT_IN_RANGE="true"
        fi
    fi
fi

# Write results
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "John Zenon",
    "a48_found": $A48_FOUND,
    "a48_active": $A48_ACTIVE,
    "a48_code": "$A48_CODE",
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_temperature": "$EVAL_TEMP",
    "evaluation_has_high_fever": $EVAL_HAS_HIGH_FEVER,
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "prescription_found": $PRESC_FOUND,
    "antibiotic_found": $ABX_FOUND,
    "antibiotic_name": "$ABX_NAME",
    "appointment_found": $APPT_FOUND,
    "appointment_date": "$APPT_DATE",
    "appointment_days_from_today": $APPT_DAYS_DIFF,
    "appointment_in_range": $APPT_IN_RANGE
}
EOF

cp "$TEMP_JSON" /tmp/occupational_legionellosis_response_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/occupational_legionellosis_response_result.json
chmod 666 /tmp/occupational_legionellosis_response_result.json 2>/dev/null || sudo chmod 666 /tmp/occupational_legionellosis_response_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="