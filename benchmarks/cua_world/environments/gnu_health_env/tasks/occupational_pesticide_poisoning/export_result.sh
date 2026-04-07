#!/bin/bash
echo "=== Exporting occupational_pesticide_poisoning result ==="

source /workspace/scripts/task_utils.sh

# Record final screenshot
take_screenshot /tmp/pest_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/pest_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/pest_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/pest_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/pest_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/pest_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/pest_target_patient_id 2>/dev/null || echo "0")

# Fetch Target Patient Name for safety checks
TARGET_NAME=$(gnuhealth_db_query "
    SELECT pp.name, pp.lastname
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID
    LIMIT 1" 2>/dev/null | tr '|' ' ')

# --- Check 1: T60.x Diagnosis (new, active) ---
T60_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'T60%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

T60_FOUND="false"
T60_ACTIVE="false"
T60_CODE="null"
if [ -n "$T60_RECORD" ]; then
    T60_FOUND="true"
    T60_CODE=$(echo "$T60_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$T60_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        T60_ACTIVE="true"
    fi
fi

# Fallback check: any new disease
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Clinical Evaluation (bradycardia: HR <= 60) ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(heart_rate::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_HR="null"
if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi

# --- Check 3: Atropine Antidote Prescription ---
PRESC_FOUND="false"
ATROPINE_FOUND="false"
ATROPINE_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"
    ATROPINE_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND LOWER(pt.name) LIKE '%atropine%'
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$ATROPINE_CHECK" ]; then
        ATROPINE_FOUND="true"
        ATROPINE_NAME="$ATROPINE_CHECK"
    fi
fi

# --- Check 4: Toxicology / Monitoring Labs (>= 2) ---
NEW_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $TARGET_PATIENT_ID
      AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 5: Follow-up Appointment (1-5 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date, (appointment_date::date - CURRENT_DATE) as days_diff
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS_DIFF="null"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DAYS_DIFF=$(echo "$APPT_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi

# Generate JSON
TEMP_JSON=$(mktemp /tmp/pest_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "$(json_escape "$TARGET_NAME")",
    "t60_found": $T60_FOUND,
    "t60_code": "$T60_CODE",
    "t60_active": $T60_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_heart_rate": "$EVAL_HR",
    "prescription_found": $PRESC_FOUND,
    "atropine_found": $ATROPINE_FOUND,
    "atropine_name": "$(json_escape "$ATROPINE_NAME")",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "appointment_found": $APPT_FOUND,
    "appointment_days_diff": "$APPT_DAYS_DIFF"
}
EOF

safe_write_result /tmp/occupational_pesticide_poisoning_result.json "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/occupational_pesticide_poisoning_result.json