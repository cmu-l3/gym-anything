#!/bin/bash
echo "=== Exporting occupational_diver_decompression_illness result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/occ_diver_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/occ_diver_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/occ_diver_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/occ_diver_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/occ_diver_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/occ_diver_target_patient_id 2>/dev/null || echo "0")

# Identify patient name
TARGET_PATIENT_NAME=$(gnuhealth_db_query "SELECT CONCAT(name, ' ', lastname) FROM party_party WHERE id = (SELECT party FROM gnuhealth_patient WHERE id = $TARGET_PATIENT_ID LIMIT 1)" 2>/dev/null)

# --- Check 1: Decompression Sickness T70.x diagnosis ---
T70_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'T70%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

T70_FOUND="false"
T70_CODE="null"
T70_ACTIVE="false"
if [ -n "$T70_RECORD" ]; then
    T70_FOUND="true"
    T70_CODE=$(echo "$T70_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$T70_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        T70_ACTIVE="true"
    fi
fi

T70_3_SPECIFIC="false"
if [ "$T70_FOUND" = "true" ]; then
    case "$T70_CODE" in
        T70.3*) T70_3_SPECIFIC="true" ;;
    esac
fi

# --- Check 2: Clinical evaluation ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(heart_rate::text,'null'), COALESCE(respiratory_rate::text,'null'), COALESCE(oxygen_saturation::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_HR="null"
EVAL_RR="null"
EVAL_SPO2="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_RR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    EVAL_SPO2=$(echo "$EVAL_RECORD" | awk -F'|' '{print $4}' | tr -d ' ')
fi

# --- Check 3: Acute therapy prescription (Oxygen or Sodium Chloride) ---
PRESC_FOUND="false"
THERAPY_FOUND="false"
THERAPY_DRUG_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    THERAPY_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%oxygen%'
               OR LOWER(pt.name) LIKE '%sodium chloride%'
               OR LOWER(pt.name) LIKE '%nacl%'
               OR LOWER(pt.name) LIKE '%saline%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$THERAPY_CHECK" ]; then
        THERAPY_FOUND="true"
        THERAPY_DRUG_NAME="$THERAPY_CHECK"
    fi
fi

# --- Check 4: Laboratory workup (>= 2) ---
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

# --- Check 5: Reassessment follow-up (1-2 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date, (appointment_date::date - CURRENT_DATE) AS diff_days
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DIFF_DAYS="-999"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DIFF_DAYS=$(echo "$APPT_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi

# ==============================================================================
# Construct JSON Result
# ==============================================================================
TEMP_JSON=$(mktemp /tmp/occ_diver_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_patient_name": "$TARGET_PATIENT_NAME",
    "t70_found": $T70_FOUND,
    "t70_active": $T70_ACTIVE,
    "t70_code": "$T70_CODE",
    "t70_3_specific": $T70_3_SPECIFIC,
    "evaluation_found": $EVAL_FOUND,
    "evaluation_heart_rate": "$EVAL_HR",
    "evaluation_respiratory_rate": "$EVAL_RR",
    "evaluation_oxygen_saturation": "$EVAL_SPO2",
    "prescription_found": $PRESC_FOUND,
    "therapy_found": $THERAPY_FOUND,
    "therapy_drug_name": "$THERAPY_DRUG_NAME",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "appointment_found": $APPT_FOUND,
    "appointment_diff_days": $APPT_DIFF_DAYS
}
EOF

# Move to final location safely
rm -f /tmp/occupational_diver_decompression_illness_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_diver_decompression_illness_result.json
chmod 666 /tmp/occupational_diver_decompression_illness_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="