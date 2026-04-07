#!/bin/bash
echo "=== Exporting agricultural_zoonotic_brucellosis result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/bruc_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/bruc_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/bruc_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/bruc_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/bruc_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/bruc_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/bruc_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/bruc_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID
    LIMIT 1" 2>/dev/null)

# --- Check 1: A23 Brucellosis diagnosis ---
A23_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'A23%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

A23_FOUND="false"
A23_CODE="null"
A23_ACTIVE="false"
if [ -n "$A23_RECORD" ]; then
    A23_FOUND="true"
    A23_CODE=$(echo "$A23_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$A23_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        A23_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "A23 diagnosis: found=$A23_FOUND code=$A23_CODE active=$A23_ACTIVE, any new: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Clinical evaluation with fever ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(temperature::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_TEMP="null"
EVAL_HAS_FEVER="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_TEMP=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    if echo "$EVAL_TEMP" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        FEVER_CHECK=$(echo "$EVAL_TEMP" | awk '{if ($1 >= 38.0) print "true"; else print "false"}')
        EVAL_HAS_FEVER="${FEVER_CHECK:-false}"
    fi
fi
echo "Evaluation: found=$EVAL_FOUND, temp=$EVAL_TEMP, fever=$EVAL_HAS_FEVER"

# --- Check 3: Dual Antibiotic Prescription ---
DOXY_FOUND="false"
RIF_FOUND="false"
PRESC_FOUND="false"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    DOXY_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order_line pol
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE pol.name = $NEW_PRESC_ID
          AND (LOWER(pt.name) LIKE '%doxycyclin%' OR LOWER(pt.name) LIKE '%tetracyclin%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$DOXY_CHECK" ]; then
        DOXY_FOUND="true"
    fi

    RIF_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order_line pol
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE pol.name = $NEW_PRESC_ID
          AND (LOWER(pt.name) LIKE '%rifampicin%' OR LOWER(pt.name) LIKE '%rifampin%' OR LOWER(pt.name) LIKE '%streptomycin%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$RIF_CHECK" ]; then
        RIF_FOUND="true"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Doxycycline: $DOXY_FOUND, Rifampicin: $RIF_FOUND"

# --- Check 4: Diagnostic Laboratory Orders (>= 3) ---
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

# --- Check 5: Follow-up Appointment (28-45 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

APPT_FOUND="false"
APPT_DAYS_OUT="0"
APPT_DATE="none"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    # GNU Health typically stores datetime. Extract just date.
    APPT_DATE=$(echo "$APPT_RECORD" | cut -d' ' -f1)
    
    # Calculate days out
    if date -d "$APPT_DATE" >/dev/null 2>&1; then
        START_TS=$(date -d "$TASK_START_DATE" +%s)
        APPT_TS=$(date -d "$APPT_DATE" +%s)
        DIFF_SEC=$((APPT_TS - START_TS))
        APPT_DAYS_OUT=$((DIFF_SEC / 86400))
    fi
fi
echo "Appointment: found=$APPT_FOUND, date=$APPT_DATE, days_out=$APPT_DAYS_OUT"

# --- JSON Export ---
TEMP_JSON=$(mktemp /tmp/bruc_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "${TARGET_PATIENT_NAME:-none}",
    "a23_found": $A23_FOUND,
    "a23_code": "$A23_CODE",
    "a23_active": $A23_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_temperature": "$EVAL_TEMP",
    "evaluation_has_fever": $EVAL_HAS_FEVER,
    "prescription_found": $PRESC_FOUND,
    "doxycycline_found": $DOXY_FOUND,
    "rifampicin_found": $RIF_FOUND,
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "appt_found": $APPT_FOUND,
    "appt_date": "$APPT_DATE",
    "appt_days_out": ${APPT_DAYS_OUT:-0}
}
EOF

rm -f /tmp/agricultural_zoonotic_brucellosis_result.json 2>/dev/null || sudo rm -f /tmp/agricultural_zoonotic_brucellosis_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/agricultural_zoonotic_brucellosis_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/agricultural_zoonotic_brucellosis_result.json
chmod 666 /tmp/agricultural_zoonotic_brucellosis_result.json 2>/dev/null || sudo chmod 666 /tmp/agricultural_zoonotic_brucellosis_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "JSON saved to /tmp/agricultural_zoonotic_brucellosis_result.json"
cat /tmp/agricultural_zoonotic_brucellosis_result.json
echo "=== Export complete ==="