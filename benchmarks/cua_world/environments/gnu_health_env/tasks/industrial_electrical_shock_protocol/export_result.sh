#!/bin/bash
echo "=== Exporting industrial_electrical_shock_protocol result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/ies_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/ies_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/ies_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/ies_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/ies_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/ies_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/ies_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/ies_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Electrocution Diagnosis (T75.4 or W86) ---
SHOCK_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'T75%' OR gpath.code LIKE 'W86%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

SHOCK_FOUND="false"
SHOCK_CODE="null"
SHOCK_ACTIVE="false"
if [ -n "$SHOCK_RECORD" ]; then
    SHOCK_FOUND="true"
    SHOCK_CODE=$(echo "$SHOCK_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$SHOCK_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        SHOCK_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Clinical evaluation with specific HR ---
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

# --- Check 3: Laboratory workup (>= 2) ---
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

# --- Check 4: Prescription (Analgesic or Burn Care) ---
PRESC_FOUND="false"
DRUG_FOUND="false"
DRUG_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    DRUG_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%ibuprofen%'
               OR LOWER(pt.name) LIKE '%acetaminophen%'
               OR LOWER(pt.name) LIKE '%paracetamol%'
               OR LOWER(pt.name) LIKE '%naproxen%'
               OR LOWER(pt.name) LIKE '%ketorolac%'
               OR LOWER(pt.name) LIKE '%diclofenac%'
               OR LOWER(pt.name) LIKE '%meloxicam%'
               OR LOWER(pt.name) LIKE '%celecoxib%'
               OR LOWER(pt.name) LIKE '%silver%sulfadiaz%'
               OR LOWER(pt.name) LIKE '%bacitracin%'
               OR LOWER(pt.name) LIKE '%tramadol%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$DRUG_CHECK" ]; then
        DRUG_FOUND="true"
        DRUG_NAME="$DRUG_CHECK"
    fi
fi

# --- Check 5: Follow-up appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(appointment_date::date::text, 'none')
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="none"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi

# Fetch patient name for reporting
TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID
" 2>/dev/null | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Write JSON output
TEMP_JSON=$(mktemp /tmp/ies_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_date": "$TASK_START_DATE",
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_patient_name": "$TARGET_PATIENT_NAME",
    "shock_found": $SHOCK_FOUND,
    "shock_code": "$SHOCK_CODE",
    "shock_active": $SHOCK_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_heart_rate": "$EVAL_HR",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "prescription_found": $PRESC_FOUND,
    "drug_found": $DRUG_FOUND,
    "drug_name": "$(json_escape "$DRUG_NAME")",
    "appointment_found": $APPT_FOUND,
    "appointment_date": "$APPT_DATE"
}
EOF

safe_write_result /tmp/industrial_electrical_shock_protocol_result.json "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="