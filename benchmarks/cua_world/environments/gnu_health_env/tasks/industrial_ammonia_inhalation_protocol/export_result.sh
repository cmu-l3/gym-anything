#!/bin/bash
echo "=== Exporting industrial_ammonia_inhalation_protocol result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/ammonia_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/ammonia_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/ammonia_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/ammonia_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/ammonia_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/ammonia_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/ammonia_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/ammonia_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Inhalation Injury Diagnosis (J68.x or T59.x) ---
TOXIC_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'J68%' OR gpath.code LIKE 'T59%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

TOXIC_FOUND="false"
TOXIC_CODE="null"
TOXIC_ACTIVE="false"
if [ -n "$TOXIC_RECORD" ]; then
    TOXIC_FOUND="true"
    TOXIC_CODE=$(echo "$TOXIC_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$TOXIC_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        TOXIC_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Clinical evaluation with RR >= 24 and O2 <= 94 ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(respiratory_rate::text,'null'), COALESCE(osat::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_RR="null"
EVAL_O2="null"
EVAL_HAS_TACHYPNEA="false"
EVAL_HAS_HYPOXIA="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_RR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_O2=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')

    if echo "$EVAL_RR" | grep -qE '^[0-9]+$'; then
        TACHY_CHECK=$(echo "$EVAL_RR" | awk '{if ($1 >= 24) print "true"; else print "false"}')
        EVAL_HAS_TACHYPNEA="${TACHY_CHECK:-false}"
    fi

    if echo "$EVAL_O2" | grep -qE '^[0-9]+$'; then
        HYPO_CHECK=$(echo "$EVAL_O2" | awk '{if ($1 <= 94) print "true"; else print "false"}')
        EVAL_HAS_HYPOXIA="${HYPO_CHECK:-false}"
    fi
fi

# --- Check 3: Rescue Medication Prescription ---
PRESC_FOUND="false"
RESCUE_MED_FOUND="false"
RESCUE_MED_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    MED_CHECK=$(gnuhealth_db_query "
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
               OR LOWER(pt.name) LIKE '%prednisone%'
               OR LOWER(pt.name) LIKE '%dexamethasone%'
               OR LOWER(pt.name) LIKE '%budesonide%'
               OR LOWER(pt.name) LIKE '%ipratropium%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$MED_CHECK" ]; then
        RESCUE_MED_FOUND="true"
        RESCUE_MED_NAME="$MED_CHECK"
    fi
fi

# --- Check 4: Diagnostic lab orders (need >= 2) ---
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

# --- Check 5: Follow-up Appointment (7-14 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date::date, (appointment_date::date - CURRENT_DATE) as diff
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS_OUT="-1"
APPT_IN_RANGE="false"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DAYS_OUT=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')

    if [ "$APPT_DAYS_OUT" -ge 7 ] && [ "$APPT_DAYS_OUT" -le 14 ]; then
        APPT_IN_RANGE="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": "$TARGET_PATIENT_ID",
    "target_patient_name": "John Zenon",
    "toxic_diagnosis_found": $TOXIC_FOUND,
    "toxic_diagnosis_code": "$TOXIC_CODE",
    "toxic_diagnosis_active": $TOXIC_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_respiratory_rate": "$EVAL_RR",
    "evaluation_has_tachypnea": $EVAL_HAS_TACHYPNEA,
    "evaluation_o2_sat": "$EVAL_O2",
    "evaluation_has_hypoxia": $EVAL_HAS_HYPOXIA,
    "prescription_found": $PRESC_FOUND,
    "rescue_medication_found": $RESCUE_MED_FOUND,
    "rescue_medication_name": "$RESCUE_MED_NAME",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "appointment_found": $APPT_FOUND,
    "appointment_days_out": $APPT_DAYS_OUT,
    "appointment_in_range": $APPT_IN_RANGE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/industrial_ammonia_inhalation_protocol_result.json 2>/dev/null || sudo rm -f /tmp/industrial_ammonia_inhalation_protocol_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/industrial_ammonia_inhalation_protocol_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/industrial_ammonia_inhalation_protocol_result.json
chmod 666 /tmp/industrial_ammonia_inhalation_protocol_result.json 2>/dev/null || sudo chmod 666 /tmp/industrial_ammonia_inhalation_protocol_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/industrial_ammonia_inhalation_protocol_result.json"
cat /tmp/industrial_ammonia_inhalation_protocol_result.json
echo "=== Export Complete ==="