#!/bin/bash
echo "=== Exporting occupational_corneal_foreign_body result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/ocfb_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/ocfb_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/ocfb_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/ocfb_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/ocfb_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/ocfb_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/ocfb_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: T15 Diagnosis (new, active) ---
T15_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'T15%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC
    LIMIT 1" 2>/dev/null | head -1)

T15_FOUND="false"
T15_ACTIVE="false"
T15_CODE="null"
if [ -n "$T15_RECORD" ]; then
    T15_FOUND="true"
    T15_CODE=$(echo "$T15_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$T15_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        T15_ACTIVE="true"
    fi
fi

# Any new disease (fallback)
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "T15 found: $T15_FOUND (code=$T15_CODE, active=$T15_ACTIVE), Any new disease: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Clinical Evaluation (HR >= 90 and context) ---
# Retrieve the newest eval record for the patient
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(heart_rate::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_HR="null"
EVAL_HAS_ELEVATED_HR="false"
EVAL_HAS_CONTEXT="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_ID=$(echo "$EVAL_RECORD" | awk -F'|' '{print $1}' | tr -d ' ')
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')

    if echo "$EVAL_HR" | grep -qE '^[0-9]+$'; then
        HR_CHECK=$(echo "$EVAL_HR" | awk '{if ($1 >= 90) print "true"; else print "false"}')
        EVAL_HAS_ELEVATED_HR="${HR_CHECK:-false}"
    fi

    # Check for context strings 'ppe' or 'metal' in the entire row's text representation
    CONTEXT_CHECK=$(gnuhealth_db_query "
        SELECT 1
        FROM gnuhealth_patient_evaluation e
        WHERE e.id = $EVAL_ID
          AND (e::text ILIKE '%ppe%' OR e::text ILIKE '%metal%')
    " 2>/dev/null | tr -d '[:space:]')

    if [ "$CONTEXT_CHECK" = "1" ]; then
        EVAL_HAS_CONTEXT="true"
    fi
fi
echo "Evaluation: found=$EVAL_FOUND, HR=$EVAL_HR (Elevated=$EVAL_HAS_ELEVATED_HR), Context=$EVAL_HAS_CONTEXT"

# --- Check 3: Prescription with >= 2 distinct medicaments ---
PRESC_FOUND="false"
PRESC_MED_COUNT=0
MED_NAMES="none"

NEW_PRESC=$(gnuhealth_db_query "
    SELECT po.id, COUNT(DISTINCT pol.medicament)
    FROM gnuhealth_prescription_order po
    LEFT JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
    WHERE po.patient = $TARGET_PATIENT_ID
      AND po.id > $BASELINE_PRESCRIPTION_MAX
    GROUP BY po.id
    ORDER BY po.id DESC LIMIT 1" 2>/dev/null | head -1)

if [ -n "$NEW_PRESC" ]; then
    PRESC_FOUND="true"
    PRESC_ID=$(echo "$NEW_PRESC" | awk -F'|' '{print $1}' | tr -d ' ')
    PRESC_MED_COUNT=$(echo "$NEW_PRESC" | awk -F'|' '{print $2}' | tr -d ' ')
    
    # Get names of prescribed items for context/feedback
    if [ "$PRESC_MED_COUNT" -gt 0 ]; then
        MED_NAMES=$(gnuhealth_db_query "
            SELECT pt.name
            FROM gnuhealth_prescription_order_line pol
            JOIN gnuhealth_medicament med ON pol.medicament = med.id
            JOIN product_product pp ON med.name = pp.id
            JOIN product_template pt ON pp.template = pt.id
            WHERE pol.name = $PRESC_ID
        " 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    fi
fi
echo "Prescription: found=$PRESC_FOUND, meds_count=$PRESC_MED_COUNT ($MED_NAMES)"

# --- Check 4: Follow-up Appointment (1-2 days) ---
APPT_FOUND="false"
APPT_DAYS_DIFF="none"
APPT_IN_WINDOW="false"

APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date - CURRENT_DATE
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DAYS_DIFF=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    
    if [ "$APPT_DAYS_DIFF" = "1" ] || [ "$APPT_DAYS_DIFF" = "2" ]; then
        APPT_IN_WINDOW="true"
    fi
fi
echo "Appointment: found=$APPT_FOUND, days_diff=$APPT_DAYS_DIFF, in_window=$APPT_IN_WINDOW"

# --- Generate JSON Result ---
TEMP_JSON=$(mktemp /tmp/ocfb_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "t15_found": $T15_FOUND,
    "t15_code": "$T15_CODE",
    "t15_active": $T15_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_heart_rate": "$EVAL_HR",
    "evaluation_has_elevated_hr": $EVAL_HAS_ELEVATED_HR,
    "evaluation_has_context": $EVAL_HAS_CONTEXT,
    "prescription_found": $PRESC_FOUND,
    "prescription_med_count": ${PRESC_MED_COUNT:-0},
    "prescription_med_names": "$MED_NAMES",
    "appointment_found": $APPT_FOUND,
    "appointment_days_diff": "$APPT_DAYS_DIFF",
    "appointment_in_window": $APPT_IN_WINDOW,
    "task_start_time": $(cat /tmp/task_start_time 2>/dev/null || echo "0"),
    "task_end_time": $(date +%s)
}
EOF

# Move and set permissions
rm -f /tmp/occupational_corneal_foreign_body_result.json 2>/dev/null || sudo rm -f /tmp/occupational_corneal_foreign_body_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_corneal_foreign_body_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/occupational_corneal_foreign_body_result.json
chmod 666 /tmp/occupational_corneal_foreign_body_result.json 2>/dev/null || sudo chmod 666 /tmp/occupational_corneal_foreign_body_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/occupational_corneal_foreign_body_result.json"
cat /tmp/occupational_corneal_foreign_body_result.json
echo "=== Export Complete ==="