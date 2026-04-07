#!/bin/bash
echo "=== Exporting occupational_rabies_pep result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/rabies_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/rabies_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/rabies_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_VACCINATION_MAX=$(cat /tmp/rabies_baseline_vaccination_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/rabies_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/rabies_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/rabies_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# Check if target patient exists
PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname, ''))
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID LIMIT 1" 2>/dev/null | tr -d '\n')

# --- Check 1: W54 Animal Bite ---
W54_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'W54%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

W54_FOUND="false"
W54_CODE="none"
W54_ACTIVE="false"
if [ -n "$W54_RECORD" ]; then
    W54_FOUND="true"
    W54_CODE=$(echo "$W54_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$W54_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        W54_ACTIVE="true"
    fi
fi

# --- Check 2: Z20.3 Rabies Exposure ---
Z20_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'Z20.3%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

Z20_FOUND="false"
Z20_CODE="none"
Z20_ACTIVE="false"
if [ -n "$Z20_RECORD" ]; then
    Z20_FOUND="true"
    Z20_CODE=$(echo "$Z20_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$Z20_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        Z20_ACTIVE="true"
    fi
fi

# --- Check 3: Amoxicillin Prescription ---
AMOX_CHECK=$(gnuhealth_db_query "
    SELECT pt.name
    FROM gnuhealth_prescription_order po
    JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
    JOIN gnuhealth_medicament med ON pol.medicament = med.id
    JOIN product_product pp ON med.name = pp.id
    JOIN product_template pt ON pp.template = pt.id
    WHERE po.patient = $TARGET_PATIENT_ID
      AND po.id > $BASELINE_PRESCRIPTION_MAX
      AND (LOWER(pt.name) LIKE '%amoxicillin%' OR LOWER(pt.name) LIKE '%clavulanate%')
    LIMIT 1" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

AMOX_FOUND="false"
AMOX_NAME="none"
if [ -n "$AMOX_CHECK" ]; then
    AMOX_FOUND="true"
    AMOX_NAME=$(echo "$AMOX_CHECK" | sed 's/"/\\"/g')
fi

# --- Check 4: Tetanus Prophylaxis (Prescription or Vaccination) ---
TET_PRESC=$(gnuhealth_db_query "
    SELECT pt.name
    FROM gnuhealth_prescription_order po
    JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
    JOIN gnuhealth_medicament med ON pol.medicament = med.id
    JOIN product_product pp ON med.name = pp.id
    JOIN product_template pt ON pp.template = pt.id
    WHERE po.patient = $TARGET_PATIENT_ID
      AND po.id > $BASELINE_PRESCRIPTION_MAX
      AND LOWER(pt.name) LIKE '%tetanus%'
    LIMIT 1" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

TET_VACC=$(gnuhealth_db_query "
    SELECT pt.name
    FROM gnuhealth_vaccination v
    JOIN gnuhealth_medicament med ON v.vaccine = med.id
    JOIN product_product pp ON med.name = pp.id
    JOIN product_template pt ON pp.template = pt.id
    WHERE (v.name = $TARGET_PATIENT_ID OR v.patient = $TARGET_PATIENT_ID)
      AND v.id > $BASELINE_VACCINATION_MAX
      AND LOWER(pt.name) LIKE '%tetanus%'
    LIMIT 1" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

TET_FOUND="false"
TET_SOURCE="none"
TET_NAME="none"
if [ -n "$TET_PRESC" ]; then
    TET_FOUND="true"
    TET_SOURCE="prescription"
    TET_NAME=$(echo "$TET_PRESC" | sed 's/"/\\"/g')
elif [ -n "$TET_VACC" ]; then
    TET_FOUND="true"
    TET_SOURCE="vaccination"
    TET_NAME=$(echo "$TET_VACC" | sed 's/"/\\"/g')
fi

# --- Check 5: Appointments Series ---
NEW_APPT_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Build JSON output ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_patient_name": "$PATIENT_NAME",
    "w54_found": $W54_FOUND,
    "w54_code": "$W54_CODE",
    "w54_active": $W54_ACTIVE,
    "z20_found": $Z20_FOUND,
    "z20_code": "$Z20_CODE",
    "z20_active": $Z20_ACTIVE,
    "amox_found": $AMOX_FOUND,
    "amox_name": "$AMOX_NAME",
    "tet_found": $TET_FOUND,
    "tet_source": "$TET_SOURCE",
    "tet_name": "$TET_NAME",
    "new_appt_count": ${NEW_APPT_COUNT:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move securely
rm -f /tmp/occupational_rabies_pep_result.json 2>/dev/null || sudo rm -f /tmp/occupational_rabies_pep_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_rabies_pep_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/occupational_rabies_pep_result.json
chmod 666 /tmp/occupational_rabies_pep_result.json 2>/dev/null || sudo chmod 666 /tmp/occupational_rabies_pep_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/occupational_rabies_pep_result.json