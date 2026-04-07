#!/bin/bash
echo "=== Exporting industrial_hexavalent_chromium_exposure result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/chrome_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/chrome_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/chrome_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/chrome_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/chrome_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/chrome_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/chrome_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/chrome_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: T56.x Diagnosis ---
T_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'T56%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

T56_FOUND="false"
T56_ACTIVE="false"
T56_CODE="null"
T56_EXACT="false"

if [ -n "$T_RECORD" ]; then
    T56_FOUND="true"
    T56_CODE=$(echo "$T_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$T_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        T56_ACTIVE="true"
    fi
    if [ "$T56_CODE" = "T56.2" ]; then
        T56_EXACT="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Clinical Evaluation (Temp 37.0, HR 75) ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(temperature::text,'null'), COALESCE(heart_rate::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_TEMP="null"
EVAL_HR="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_TEMP=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi

# --- Check 3: Targeted Prescription ---
PRESC_FOUND="false"
TARGET_RX_FOUND="false"
TARGET_RX_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    RX_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%ascorbic%'
               OR LOWER(pt.name) LIKE '%vitamin c%'
               OR LOWER(pt.name) LIKE '%mupirocin%'
               OR LOWER(pt.name) LIKE '%bacitracin%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$RX_CHECK" ]; then
        TARGET_RX_FOUND="true"
        TARGET_RX_NAME="$RX_CHECK"
    fi
fi

# --- Check 4: Laboratory Orders (>= 2) ---
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

# --- Check 5: Follow-up Appointment (10-20 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="null"
DAYS_DIFF="0"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')

    # Calculate days difference from today
    if [ -n "$APPT_DATE" ] && [ "$APPT_DATE" != "null" ]; then
        TODAY_SEC=$(date -d "$TASK_START_DATE" +%s)
        APPT_SEC=$(date -d "$APPT_DATE" +%s 2>/dev/null || echo "0")
        if [ "$APPT_SEC" -gt 0 ]; then
            DAYS_DIFF=$(( (APPT_SEC - TODAY_SEC) / 86400 ))
        fi
    fi
fi

# Export all to JSON
TEMP_JSON=$(mktemp /tmp/chrome_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_patient_name": "Roberto Carlos",
    "t56_found": $T56_FOUND,
    "t56_active": $T56_ACTIVE,
    "t56_code": "$T56_CODE",
    "t56_exact": $T56_EXACT,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_temperature": "$EVAL_TEMP",
    "evaluation_heart_rate": "$EVAL_HR",
    "prescription_found": $PRESC_FOUND,
    "target_rx_found": $TARGET_RX_FOUND,
    "target_rx_name": "$TARGET_RX_NAME",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "appointment_found": $APPT_FOUND,
    "appointment_date": "$APPT_DATE",
    "appointment_days_out": $DAYS_DIFF,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safely copy to standard output location
rm -f /tmp/industrial_hexavalent_chromium_exposure_result.json 2>/dev/null || sudo rm -f /tmp/industrial_hexavalent_chromium_exposure_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/industrial_hexavalent_chromium_exposure_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/industrial_hexavalent_chromium_exposure_result.json
chmod 666 /tmp/industrial_hexavalent_chromium_exposure_result.json 2>/dev/null || sudo chmod 666 /tmp/industrial_hexavalent_chromium_exposure_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export completed. Results saved to /tmp/industrial_hexavalent_chromium_exposure_result.json"
cat /tmp/industrial_hexavalent_chromium_exposure_result.json