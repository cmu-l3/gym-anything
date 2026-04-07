#!/bin/bash
echo "=== Exporting occupational_lyme_disease_protocol result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/lyme_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/lyme_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/lyme_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/lyme_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/lyme_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/lyme_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/lyme_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/lyme_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Lyme disease A69.2 diagnosis (new, active) ---
A69_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'A69%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

A69_FOUND="false"
A69_ACTIVE="false"
A69_CODE="null"
if [ -n "$A69_RECORD" ]; then
    A69_FOUND="true"
    A69_CODE=$(echo "$A69_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$A69_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        A69_ACTIVE="true"
    fi
fi

A692_SPECIFIC="false"
if [ "$A69_FOUND" = "true" ]; then
    if [[ "$A69_CODE" == A69.2* ]]; then
        A692_SPECIFIC="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "A69 Lyme: found=$A69_FOUND code=$A69_CODE active=$A69_ACTIVE A69.2_specific=$A692_SPECIFIC, any new: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Clinical evaluation with fever ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(temperature::text,'null'), COALESCE(chief_complaint,'')
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
        FEVER_CHECK=$(echo "$EVAL_TEMP" | awk '{if ($1 >= 37.5) print "true"; else print "false"}')
        EVAL_HAS_FEVER="${FEVER_CHECK:-false}"
    fi
fi
echo "Evaluation: found=$EVAL_FOUND, temp=$EVAL_TEMP, fever_threshold_met=$EVAL_HAS_FEVER"

# --- Check 3: Antibiotic Prescription (Doxycycline/Amoxicillin/Cefuroxime) ---
PRESC_FOUND="false"
ABX_FOUND="false"
ABX_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    ABX_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%doxycyclin%'
               OR LOWER(pt.name) LIKE '%amoxicillin%'
               OR LOWER(pt.name) LIKE '%cefuroxim%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$ABX_CHECK" ]; then
        ABX_FOUND="true"
        ABX_NAME="$ABX_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Antibiotic: $ABX_FOUND ($ABX_NAME)"

# --- Check 4: Laboratory Orders (>= 1) ---
NEW_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $TARGET_PATIENT_ID
      AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')

NEW_LAB_TYPES=$(gnuhealth_db_query "
    SELECT ltt.name
    FROM gnuhealth_patient_lab_test glt
    JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
    WHERE glt.patient_id = $TARGET_PATIENT_ID
      AND glt.id > $BASELINE_LAB_MAX
    ORDER BY glt.id
" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
echo "New lab orders: ${NEW_LAB_COUNT:-0} (types: $NEW_LAB_TYPES)"

# --- Check 5: Follow-up Appointment (14-28 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date::date, EXTRACT(DAY FROM (appointment_date - CURRENT_DATE))
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="null"
APPT_DAYS="null"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $1}' | tr -d ' ')
    APPT_DAYS=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi
echo "Appointment: found=$APPT_FOUND, date=$APPT_DATE, days_from_now=$APPT_DAYS"

# --- Export JSON ---
TEMP_JSON=$(mktemp /tmp/lyme_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_patient_name": "John Zenon",
    "a69_found": $A69_FOUND,
    "a69_code": "$A69_CODE",
    "a69_active": $A69_ACTIVE,
    "a692_specific": $A692_SPECIFIC,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_temperature": "$EVAL_TEMP",
    "evaluation_has_fever": $EVAL_HAS_FEVER,
    "prescription_found": $PRESC_FOUND,
    "antibiotic_found": $ABX_FOUND,
    "antibiotic_name": "$ABX_NAME",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "appointment_found": $APPT_FOUND,
    "appointment_date": "$APPT_DATE",
    "appointment_days": "${APPT_DAYS:-0}",
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/occupational_lyme_disease_protocol_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_lyme_disease_protocol_result.json
chmod 666 /tmp/occupational_lyme_disease_protocol_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="