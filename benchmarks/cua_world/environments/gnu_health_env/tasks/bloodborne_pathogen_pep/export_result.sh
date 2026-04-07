#!/bin/bash
echo "=== Exporting bloodborne_pathogen_pep result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/pep_final_state.png ga
chmod 666 /tmp/pep_final_state.png 2>/dev/null || true

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/pep_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/pep_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/pep_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/pep_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/pep_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/pep_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# 1. Exposure diagnosis
EXPOSURE_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'W46%' OR gpath.code LIKE 'Z20%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC
    LIMIT 1" 2>/dev/null | head -1)

EXPOSURE_FOUND="false"
EXPOSURE_ACTIVE="false"
EXPOSURE_CODE="null"
if [ -n "$EXPOSURE_RECORD" ]; then
    EXPOSURE_FOUND="true"
    EXPOSURE_CODE=$(echo "$EXPOSURE_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$EXPOSURE_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        EXPOSURE_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# 2. Baseline Labs
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

# 3. Prescription
PRESC_FOUND="false"
PEP_DRUG_FOUND="false"
PEP_DRUG_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    PEP_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%zidovudine%'
               OR LOWER(pt.name) LIKE '%lamivudine%'
               OR LOWER(pt.name) LIKE '%tenofovir%'
               OR LOWER(pt.name) LIKE '%efavirenz%'
               OR LOWER(pt.name) LIKE '%raltegravir%'
               OR LOWER(pt.name) LIKE '%dolutegravir%'
               OR LOWER(pt.name) LIKE '%emtricitabine%'
               OR LOWER(pt.name) LIKE '%antiviral%'
               OR LOWER(pt.name) LIKE '%hiv%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$PEP_CHECK" ]; then
        PEP_DRUG_FOUND="true"
        PEP_DRUG_NAME="$PEP_CHECK"
    fi
fi

# 4. Appointment
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="null"
APPT_DAYS_DELTA="0"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    
    if [ -n "$APPT_DATE" ] && [ "$APPT_DATE" != "null" ]; then
        # Calculate days difference from task start date
        START_SEC=$(date -d "$TASK_START_DATE" +%s 2>/dev/null || date +%s)
        APPT_SEC=$(date -d "$APPT_DATE" +%s 2>/dev/null || echo "0")
        
        if [ "$APPT_SEC" != "0" ]; then
            APPT_DAYS_DELTA=$(( (APPT_SEC - START_SEC) / 86400 ))
        fi
    fi
fi

# Retrieve Patient Name
TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT pp.name || ' ' || COALESCE(pp.lastname,'') 
    FROM gnuhealth_patient gp 
    JOIN party_party pp ON gp.party = pp.id 
    WHERE gp.id = $TARGET_PATIENT_ID" 2>/dev/null | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Write JSON output
TEMP_JSON=$(mktemp /tmp/bloodborne_pathogen_pep_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "${TARGET_PATIENT_NAME}",
    "exposure_found": $EXPOSURE_FOUND,
    "exposure_code": "${EXPOSURE_CODE}",
    "exposure_active": $EXPOSURE_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "${NEW_LAB_TYPES}",
    "prescription_found": $PRESC_FOUND,
    "pep_drug_found": $PEP_DRUG_FOUND,
    "pep_drug_name": "${PEP_DRUG_NAME}",
    "appointment_found": $APPT_FOUND,
    "appointment_date": "${APPT_DATE}",
    "appointment_days_delta": ${APPT_DAYS_DELTA:-0}
}
EOF

rm -f /tmp/bloodborne_pathogen_pep_result.json 2>/dev/null || sudo rm -f /tmp/bloodborne_pathogen_pep_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/bloodborne_pathogen_pep_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/bloodborne_pathogen_pep_result.json
chmod 666 /tmp/bloodborne_pathogen_pep_result.json 2>/dev/null || sudo chmod 666 /tmp/bloodborne_pathogen_pep_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/bloodborne_pathogen_pep_result.json"
cat /tmp/bloodborne_pathogen_pep_result.json
echo "=== Export complete ==="