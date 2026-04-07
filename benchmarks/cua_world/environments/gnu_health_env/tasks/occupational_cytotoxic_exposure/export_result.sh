#!/bin/bash
echo "=== Exporting occupational_cytotoxic_exposure result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/cyto_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/cyto_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/cyto_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/cyto_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/cyto_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/cyto_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/cyto_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/cyto_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# Fetch patient name for verification check
TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID
" 2>/dev/null | tr -d '\n')

# --- Check 1: Toxic exposure diagnosis (T45.x or T65.x) ---
T_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'T45%' OR gpath.code LIKE 'T65%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

T_FOUND="false"
T_CODE="null"
T_ACTIVE="false"
if [ -n "$T_RECORD" ]; then
    T_FOUND="true"
    T_CODE=$(echo "$T_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$T_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        T_ACTIVE="true"
    fi
fi

# Any new disease at all
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

echo "T-code: found=$T_FOUND code=$T_CODE active=$T_ACTIVE, any new: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Clinical evaluation ---
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
echo "Evaluation: found=$EVAL_FOUND, HR=$EVAL_HR"

# --- Check 3: Toxicity labs (>= 3) ---
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

# --- Check 4: Irrigation prescription (Saline / Sodium Chloride) ---
PRESC_FOUND="false"
IRRIGATION_FOUND="false"
IRRIGATION_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    IRR_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%sodium%'
               OR LOWER(pt.name) LIKE '%chlor%'
               OR LOWER(pt.name) LIKE '%saline%'
               OR LOWER(pt.name) LIKE '%water%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$IRR_CHECK" ]; then
        IRRIGATION_FOUND="true"
        IRRIGATION_NAME="$IRR_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Irrigation: $IRRIGATION_FOUND ($IRRIGATION_NAME)"

# --- Check 5: Follow-up appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS_FROM_NOW="null"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    
    if [ -n "$APPT_DATE" ] && [ "$APPT_DATE" != "null" ]; then
        APPT_EPOCH=$(date -d "$APPT_DATE" +%s 2>/dev/null || echo "")
        TODAY_EPOCH=$(date -d "$TASK_START_DATE" +%s 2>/dev/null || echo "")
        
        if [ -n "$APPT_EPOCH" ] && [ -n "$TODAY_EPOCH" ]; then
            DIFF_SECS=$((APPT_EPOCH - TODAY_EPOCH))
            APPT_DAYS_FROM_NOW=$((DIFF_SECS / 86400))
        fi
    fi
fi
echo "Appointment found: $APPT_FOUND, Days from now: $APPT_DAYS_FROM_NOW"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_patient_name": "$(json_escape "$TARGET_PATIENT_NAME")",
    "t_code_found": $T_FOUND,
    "t_code": "$T_CODE",
    "t_code_active": $T_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_heart_rate": "$EVAL_HR",
    "prescription_found": $PRESC_FOUND,
    "irrigation_found": $IRRIGATION_FOUND,
    "irrigation_drug_name": "$(json_escape "$IRRIGATION_NAME")",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "appointment_found": $APPT_FOUND,
    "appointment_days_from_start": "$APPT_DAYS_FROM_NOW",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "/tmp/occupational_cytotoxic_exposure_result.json" "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/occupational_cytotoxic_exposure_result.json"
echo "=== Export Complete ==="