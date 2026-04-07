#!/bin/bash
echo "=== Exporting warehouse_co_exposure_management result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/co_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/co_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/co_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/co_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/co_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/co_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/co_target_patient_id 2>/dev/null || echo "0")
TARGET_PARTY_ID=$(cat /tmp/co_target_party_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/co_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID, party_id: $TARGET_PARTY_ID"

# Fetch Target Patient Name
TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM party_party pp WHERE pp.id = $TARGET_PARTY_ID" | tr -d '\n')

# --- Check 1: T58 CO Poisoning Diagnosis (new, active) ---
T58_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'T58%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

T58_FOUND="false"
T58_ACTIVE="false"
T58_CODE="null"
if [ -n "$T58_RECORD" ]; then
    T58_FOUND="true"
    T58_CODE=$(echo "$T58_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$T58_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        T58_ACTIVE="true"
    fi
fi

# Any new disease at all for partial credit
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

echo "T58 CO Poisoning: found=$T58_FOUND code=$T58_CODE active=$T58_ACTIVE, any new: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Clinical evaluation with tachycardia and tachypnea ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(heart_rate::text,'null'), COALESCE(respiratory_rate::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_HR="null"
EVAL_RR="null"
EVAL_HAS_TACHYCARDIA="false"
EVAL_HAS_TACHYPNEA="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_RR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')

    if echo "$EVAL_HR" | grep -qE '^[0-9]+$'; then
        TACHYCARDIA_CHECK=$(echo "$EVAL_HR" | awk '{if ($1 >= 100) print "true"; else print "false"}')
        EVAL_HAS_TACHYCARDIA="${TACHYCARDIA_CHECK:-false}"
    fi

    if echo "$EVAL_RR" | grep -qE '^[0-9]+$'; then
        TACHYPNEA_CHECK=$(echo "$EVAL_RR" | awk '{if ($1 >= 20) print "true"; else print "false"}')
        EVAL_HAS_TACHYPNEA="${TACHYPNEA_CHECK:-false}"
    fi
fi

echo "Evaluation: found=$EVAL_FOUND, HR=$EVAL_HR (tachycardia=$EVAL_HAS_TACHYCARDIA), RR=$EVAL_RR (tachypnea=$EVAL_HAS_TACHYPNEA)"

# --- Check 3: Analgesic prescription ---
PRESC_FOUND="false"
ANALGESIC_FOUND="false"
ANALGESIC_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    ANALGESIC_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%paracetamol%'
               OR LOWER(pt.name) LIKE '%ibuprofen%'
               OR LOWER(pt.name) LIKE '%acetaminophen%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$ANALGESIC_CHECK" ]; then
        ANALGESIC_FOUND="true"
        ANALGESIC_NAME="$ANALGESIC_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Analgesic: $ANALGESIC_FOUND ($ANALGESIC_NAME)"

# --- Check 4: Baseline lab orders (>= 2) ---
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

# --- Check 5: Follow-up Appointment ---
APPT_FOUND="false"
APPT_DAYS_DIFF="null"

APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date::date, (appointment_date::date - CURRENT_DATE) as days_diff
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1)

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DAYS_DIFF=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi
echo "Appointment found: $APPT_FOUND, days from today: $APPT_DAYS_DIFF"

# Export data as JSON securely
TEMP_JSON=$(mktemp /tmp/warehouse_co_exposure_management_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "${TARGET_PATIENT_NAME}",
    "t58_found": ${T58_FOUND},
    "t58_active": ${T58_ACTIVE},
    "t58_code": "${T58_CODE}",
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": ${EVAL_FOUND},
    "evaluation_heart_rate": "${EVAL_HR}",
    "evaluation_respiratory_rate": "${EVAL_RR}",
    "evaluation_has_tachycardia": ${EVAL_HAS_TACHYCARDIA},
    "evaluation_has_tachypnea": ${EVAL_HAS_TACHYPNEA},
    "prescription_found": ${PRESC_FOUND},
    "analgesic_found": ${ANALGESIC_FOUND},
    "analgesic_name": "${ANALGESIC_NAME}",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "${NEW_LAB_TYPES}",
    "appointment_found": ${APPT_FOUND},
    "appointment_days_diff": "${APPT_DAYS_DIFF}",
    "task_start_date": "${TASK_START_DATE}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result /tmp/warehouse_co_exposure_management_result.json "$(cat $TEMP_JSON)"

echo "Result JSON saved to /tmp/warehouse_co_exposure_management_result.json"
cat /tmp/warehouse_co_exposure_management_result.json

echo "=== Export Complete ==="