#!/bin/bash
echo "=== Exporting occupational_byssinosis_management result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/byss_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/byss_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/byss_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/byss_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/byss_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/byss_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/byss_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# Check if application was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# --- Check 1: J66.x Byssinosis diagnosis (new, active) ---
J66_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'J66%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

J66_FOUND="false"
J66_ACTIVE="false"
J66_CODE="null"
if [ -n "$J66_RECORD" ]; then
    J66_FOUND="true"
    J66_CODE=$(echo "$J66_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$J66_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        J66_ACTIVE="true"
    fi
fi

# Count any new disease
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "J66 diagnosis: found=$J66_FOUND code=$J66_CODE active=$J66_ACTIVE, any new disease: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Clinical evaluation with chest tightness / cough ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(chief_complaint,'')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_CHIEF="null"
EVAL_HAS_CHEST="false"
EVAL_HAS_COUGH="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_CHIEF=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}')
    
    # Case insensitive matching for keywords
    if echo "$EVAL_CHIEF" | grep -qiE 'chest|tightness'; then
        EVAL_HAS_CHEST="true"
    fi
    if echo "$EVAL_CHIEF" | grep -qiE 'cough'; then
        EVAL_HAS_COUGH="true"
    fi
fi
echo "Evaluation: found=$EVAL_FOUND, chief_complaint='$EVAL_CHIEF', has_chest=$EVAL_HAS_CHEST, has_cough=$EVAL_HAS_COUGH"

# --- Check 3: Diagnostic Labs (>= 2) ---
NEW_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $TARGET_PATIENT_ID
      AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')

NEW_LAB_TYPES=$(gnuhealth_db_query "
    SELECT ltt.code
    FROM gnuhealth_patient_lab_test glt
    JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
    WHERE glt.patient_id = $TARGET_PATIENT_ID
      AND glt.id > $BASELINE_LAB_MAX
    ORDER BY glt.id
" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
echo "New lab orders: ${NEW_LAB_COUNT:-0} (types: $NEW_LAB_TYPES)"

# --- Check 4: Respiratory Medication Prescription ---
PRESC_FOUND="false"
RESP_MED_FOUND="false"
RESP_DRUG_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    RESP_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%albuterol%'
               OR LOWER(pt.name) LIKE '%salbutamol%'
               OR LOWER(pt.name) LIKE '%fluticasone%'
               OR LOWER(pt.name) LIKE '%budesonide%'
               OR LOWER(pt.name) LIKE '%ipratropium%'
               OR LOWER(pt.name) LIKE '%tiotropium%'
               OR LOWER(pt.name) LIKE '%salmeterol%'
               OR LOWER(pt.name) LIKE '%formoterol%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$RESP_CHECK" ]; then
        RESP_MED_FOUND="true"
        RESP_DRUG_NAME="$RESP_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Resp Med: $RESP_MED_FOUND ($RESP_DRUG_NAME)"

# --- Check 5: Follow-up Appointment (14-30 days) ---
APPT_FOUND="false"
APPT_DIFF_DAYS="-999"

APPT_RECORD=$(gnuhealth_db_query "
    SELECT DATE_PART('day', appointment_date::timestamp - '$TASK_START_DATE'::timestamp)
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | tr -d '[:space:]')

if [ -n "$APPT_RECORD" ] && [ "$APPT_RECORD" != "null" ]; then
    APPT_FOUND="true"
    APPT_DIFF_DAYS="$APPT_RECORD"
fi
echo "Appointment found: $APPT_FOUND, Diff days: $APPT_DIFF_DAYS"


# --- Write JSON Result ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_patient_name": "Ana Betz",
    "j66_found": $J66_FOUND,
    "j66_active": $J66_ACTIVE,
    "j66_code": "$J66_CODE",
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_has_chest": $EVAL_HAS_CHEST,
    "evaluation_has_cough": $EVAL_HAS_COUGH,
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "prescription_found": $PRESC_FOUND,
    "respiratory_med_found": $RESP_MED_FOUND,
    "respiratory_drug_name": "$RESP_DRUG_NAME",
    "appointment_found": $APPT_FOUND,
    "appointment_diff_days": $APPT_DIFF_DAYS
}
EOF

rm -f /tmp/occupational_byssinosis_management_result.json 2>/dev/null || sudo rm -f /tmp/occupational_byssinosis_management_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_byssinosis_management_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/occupational_byssinosis_management_result.json
chmod 666 /tmp/occupational_byssinosis_management_result.json 2>/dev/null || sudo chmod 666 /tmp/occupational_byssinosis_management_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/occupational_byssinosis_management_result.json"
cat /tmp/occupational_byssinosis_management_result.json
echo "=== Export complete ==="