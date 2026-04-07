#!/bin/bash
echo "=== Exporting occupational_ergonomic_rsi_management result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/rsi_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/rsi_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/rsi_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/rsi_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/rsi_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/rsi_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/rsi_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/rsi_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# Fetch Target Patient Name
TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID
" 2>/dev/null | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# --- Check 1: Carpal Tunnel G56.x diagnosis ---
G56_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'G56%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

G56_FOUND="false"
G56_CODE="null"
G56_ACTIVE="false"
if [ -n "$G56_RECORD" ]; then
    G56_FOUND="true"
    G56_CODE=$(echo "$G56_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$G56_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        G56_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Clinical evaluation with Heart Rate ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(heart_rate::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_HR="null"
EVAL_HR_VALID="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')

    if echo "$EVAL_HR" | grep -qE '^[0-9]+$'; then
        HR_CHECK=$(echo "$EVAL_HR" | awk '{if ($1 >= 60 && $1 <= 100) print "true"; else print "false"}')
        EVAL_HR_VALID="${HR_CHECK:-false}"
    fi
fi

# --- Check 3: Analgesic / NSAID prescription ---
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
               OR LOWER(pt.name) LIKE '%naproxen%'
               OR LOWER(pt.name) LIKE '%diclofenac%'
               OR LOWER(pt.name) LIKE '%paracetamol%'
               OR LOWER(pt.name) LIKE '%acetaminophen%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$ANALGESIC_CHECK" ]; then
        ANALGESIC_FOUND="true"
        ANALGESIC_NAME="$ANALGESIC_CHECK"
    fi
fi

# --- Check 4: Diagnostic lab orders (>= 1) ---
NEW_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $TARGET_PATIENT_ID
      AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 5: Follow-up Appointment (14-30 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, (appointment_date::date - CURRENT_DATE) as diff_days
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DIFF_DAYS="null"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DIFF_DAYS=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi

# --- JSON EXPORT ---
TEMP_JSON=$(mktemp /tmp/rsi_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "${TARGET_PATIENT_NAME}",
    "g56_found": $G56_FOUND,
    "g56_code": "${G56_CODE}",
    "g56_active": $G56_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_heart_rate": "${EVAL_HR}",
    "evaluation_hr_valid": $EVAL_HR_VALID,
    "prescription_found": $PRESC_FOUND,
    "analgesic_found": $ANALGESIC_FOUND,
    "analgesic_name": "${ANALGESIC_NAME}",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "appointment_found": $APPT_FOUND,
    "appointment_diff_days": "${APPT_DIFF_DAYS}"
}
EOF

rm -f /tmp/occupational_ergonomic_rsi_management_result.json 2>/dev/null || sudo rm -f /tmp/occupational_ergonomic_rsi_management_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_ergonomic_rsi_management_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/occupational_ergonomic_rsi_management_result.json
chmod 666 /tmp/occupational_ergonomic_rsi_management_result.json 2>/dev/null || sudo chmod 666 /tmp/occupational_ergonomic_rsi_management_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/occupational_ergonomic_rsi_management_result.json"
cat /tmp/occupational_ergonomic_rsi_management_result.json
echo "=== Export Complete ==="