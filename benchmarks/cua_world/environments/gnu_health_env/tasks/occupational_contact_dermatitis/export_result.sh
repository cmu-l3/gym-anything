#!/bin/bash
echo "=== Exporting occupational_contact_dermatitis result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/occ_derm_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/occ_derm_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_ALLERGY_MAX=$(cat /tmp/occ_derm_baseline_allergy_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/occ_derm_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/occ_derm_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/occ_derm_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/occ_derm_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/occ_derm_task_start_date 2>/dev/null || date +%Y-%m-%d)

# Verify Patient Info
PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id 
    WHERE gp.id = $TARGET_PATIENT_ID LIMIT 1" | tr -d '\n' | sed 's/"/\\"/g')

echo "Target patient_id: $TARGET_PATIENT_ID ($PATIENT_NAME)"

# --- Check 1: Dermatitis Diagnosis (L23 or L24) ---
L_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'L23%' OR gpath.code LIKE 'L24%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

L_FOUND="false"
L_ACTIVE="false"
L_CODE="null"
if [ -n "$L_RECORD" ]; then
    L_FOUND="true"
    L_CODE=$(echo "$L_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$L_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        L_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Allergy / Sensitization ---
ALLERGY_RECORD=$(gnuhealth_db_query "
    SELECT id, allergen, COALESCE(severity, 'unknown')
    FROM gnuhealth_patient_allergy
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_ALLERGY_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

ALLERGY_FOUND="false"
ALLERGEN_NAME="none"
if [ -n "$ALLERGY_RECORD" ]; then
    ALLERGY_FOUND="true"
    ALLERGEN_NAME=$(echo "$ALLERGY_RECORD" | awk -F'|' '{print $2}' | sed 's/"/\\"/g')
fi

# --- Check 3: Clinical Evaluation ---
EVAL_FOUND="false"
EVAL_CHECK=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_EVAL_MAX
    LIMIT 1" 2>/dev/null | tr -d '[:space:]')
if [ -n "$EVAL_CHECK" ]; then
    EVAL_FOUND="true"
fi

# --- Check 4: Prescription (Corticosteroid / Antihistamine) ---
PRESC_FOUND="false"
DRUG_MATCH_FOUND="false"
PRESCRIBED_DRUG="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"
    DRUG_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%hydrocortisone%'
               OR LOWER(pt.name) LIKE '%loratadine%'
               OR LOWER(pt.name) LIKE '%cetirizine%'
               OR LOWER(pt.name) LIKE '%diphenhydramine%'
               OR LOWER(pt.name) LIKE '%betamethasone%'
               OR LOWER(pt.name) LIKE '%predn%'
               OR LOWER(pt.name) LIKE '%desoximetasone%'
               OR LOWER(pt.name) LIKE '%fluocinonide%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//' | sed 's/"/\\"/g')

    if [ -n "$DRUG_CHECK" ]; then
        DRUG_MATCH_FOUND="true"
        PRESCRIBED_DRUG="$DRUG_CHECK"
    fi
fi

# --- Check 5: Follow-up Appointment ---
APPT_FOUND="false"
APPT_DATES_JSON="[]"

APPT_RECORDS=$(gnuhealth_db_query "
    SELECT appointment_date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
" 2>/dev/null)

if [ -n "$APPT_RECORDS" ]; then
    APPT_FOUND="true"
    # Format array of dates
    APPT_DATES_JSON=$(echo "$APPT_RECORDS" | awk '{print "\"" $0 "\""}' | paste -sd "," - | sed 's/^/[/;s/$/]/')
    if [ "$APPT_DATES_JSON" = "[]" ] || [ -z "$APPT_DATES_JSON" ]; then APPT_DATES_JSON="[]"; fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "$PATIENT_NAME",
    "task_start_date": "$TASK_START_DATE",
    "diagnosis_found": $L_FOUND,
    "diagnosis_code": "$L_CODE",
    "diagnosis_active": $L_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "allergy_found": $ALLERGY_FOUND,
    "allergen_name": "$ALLERGEN_NAME",
    "evaluation_found": $EVAL_FOUND,
    "prescription_found": $PRESC_FOUND,
    "drug_match_found": $DRUG_MATCH_FOUND,
    "prescribed_drug": "$PRESCRIBED_DRUG",
    "appointment_found": $APPT_FOUND,
    "appointment_dates": $APPT_DATES_JSON
}
EOF

# Move to final location safely
rm -f /tmp/occupational_contact_dermatitis_result.json 2>/dev/null || sudo rm -f /tmp/occupational_contact_dermatitis_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_contact_dermatitis_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/occupational_contact_dermatitis_result.json
chmod 666 /tmp/occupational_contact_dermatitis_result.json 2>/dev/null || sudo chmod 666 /tmp/occupational_contact_dermatitis_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export saved to /tmp/occupational_contact_dermatitis_result.json"
cat /tmp/occupational_contact_dermatitis_result.json
echo "=== Export Complete ==="