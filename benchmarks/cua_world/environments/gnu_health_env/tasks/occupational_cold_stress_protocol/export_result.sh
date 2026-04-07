#!/bin/bash
echo "=== Exporting occupational_cold_stress_protocol result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/cold_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/cold_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/cold_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/cold_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/cold_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/cold_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/cold_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/cold_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Cold stress diagnosis ---
COLD_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'T33%' OR gpath.code LIKE 'T68%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

COLD_FOUND="false"
COLD_CODE="null"
COLD_ACTIVE="false"
if [ -n "$COLD_RECORD" ]; then
    COLD_FOUND="true"
    COLD_CODE=$(echo "$COLD_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$COLD_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        COLD_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Clinical evaluation with hypothermia ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(temperature::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_TEMP="null"
EVAL_HYPOTHERMIC="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_TEMP=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')

    if echo "$EVAL_TEMP" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        HYPO_CHECK=$(echo "$EVAL_TEMP" | awk '{if ($1 <= 35.5) print "true"; else print "false"}')
        EVAL_HYPOTHERMIC="${HYPO_CHECK:-false}"
    fi
fi

# --- Check 3: Baseline Labs (>= 2) ---
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

# --- Check 4: Analgesic prescription ---
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
          AND (LOWER(pt.name) LIKE '%ibuprofen%'
               OR LOWER(pt.name) LIKE '%ketorolac%'
               OR LOWER(pt.name) LIKE '%acetaminophen%'
               OR LOWER(pt.name) LIKE '%paracetamol%'
               OR LOWER(pt.name) LIKE '%aspirin%'
               OR LOWER(pt.name) LIKE '%naproxen%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$ANALGESIC_CHECK" ]; then
        ANALGESIC_FOUND="true"
        ANALGESIC_NAME="$ANALGESIC_CHECK"
    fi
fi

# --- Check 5: Tissue Check Follow-up (2-7 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS_DELTA="0"
APPT_IN_RANGE="false"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    
    if [ -n "$APPT_DATE" ]; then
        START_SEC=$(date -d "$TASK_START_DATE" +%s)
        APPT_SEC=$(date -d "$APPT_DATE" +%s 2>/dev/null || echo "$START_SEC")
        APPT_DAYS_DELTA=$(( (APPT_SEC - START_SEC) / 86400 ))
        
        if [ "$APPT_DAYS_DELTA" -ge 2 ] && [ "$APPT_DAYS_DELTA" -le 7 ]; then
            APPT_IN_RANGE="true"
        fi
    fi
fi

TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID
" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

# Write JSON output
TEMP_JSON=$(mktemp /tmp/occupational_cold_stress_protocol_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "${TARGET_PATIENT_NAME}",
    "cold_found": ${COLD_FOUND},
    "cold_code": "${COLD_CODE}",
    "cold_active": ${COLD_ACTIVE},
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": ${EVAL_FOUND},
    "evaluation_temperature": "${EVAL_TEMP}",
    "evaluation_hypothermic": ${EVAL_HYPOTHERMIC},
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "${NEW_LAB_TYPES}",
    "prescription_found": ${PRESC_FOUND},
    "analgesic_found": ${ANALGESIC_FOUND},
    "analgesic_name": "${ANALGESIC_NAME}",
    "appointment_found": ${APPT_FOUND},
    "appointment_days_delta": ${APPT_DAYS_DELTA},
    "appointment_in_range": ${APPT_IN_RANGE}
}
EOF

rm -f /tmp/occupational_cold_stress_protocol_result.json 2>/dev/null || sudo rm -f /tmp/occupational_cold_stress_protocol_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_cold_stress_protocol_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/occupational_cold_stress_protocol_result.json
chmod 666 /tmp/occupational_cold_stress_protocol_result.json 2>/dev/null || sudo chmod 666 /tmp/occupational_cold_stress_protocol_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="