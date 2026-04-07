#!/bin/bash
echo "=== Exporting occupational_travel_medicine_clearance result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final state screenshot
take_screenshot /tmp/travel_final_state.png

# 2. Load Baselines
BASELINE_DISEASE_MAX=$(cat /tmp/travel_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/travel_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_VAX_MAX=$(cat /tmp/travel_baseline_vax_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/travel_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/travel_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/travel_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/travel_task_start_date 2>/dev/null || date +%Y-%m-%d)
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || date +%s)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Prophylactic Z-code diagnosis ---
Z_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'Z29%' OR gpath.code LIKE 'Z02%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

Z_FOUND="false"
Z_CODE="null"
Z_ACTIVE="false"
if [ -n "$Z_RECORD" ]; then
    Z_FOUND="true"
    Z_CODE=$(echo "$Z_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$Z_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        Z_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Clinical evaluation with BP and HR ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(systolic::text,'null'), COALESCE(diastolic::text,'null'), COALESCE(heart_rate::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_SYS="null"
EVAL_DIA="null"
EVAL_HR="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_SYS=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_DIA=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $4}' | tr -d ' ')
fi

# --- Check 3: Travel Vaccination ---
VAX_RECORD=$(gnuhealth_db_query "
    SELECT vax.id, pt.name
    FROM gnuhealth_vaccination vax
    JOIN gnuhealth_medicament med ON vax.vaccine = med.id
    JOIN product_product pp ON med.name = pp.id
    JOIN product_template pt ON pp.template = pt.id
    WHERE vax.patient = $TARGET_PATIENT_ID
      AND vax.id > $BASELINE_VAX_MAX
    ORDER BY vax.id DESC LIMIT 1" 2>/dev/null | head -1)

VAX_FOUND="false"
VAX_NAME="none"
if [ -n "$VAX_RECORD" ]; then
    VAX_FOUND="true"
    VAX_NAME=$(echo "$VAX_RECORD" | awk -F'|' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi

# Try generic vaccination entry if the precise join fails
if [ "$VAX_FOUND" = "false" ]; then
    GENERIC_VAX=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_vaccination
        WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_VAX_MAX LIMIT 1
    " 2>/dev/null | tr -d '[:space:]')
    if [ -n "$GENERIC_VAX" ]; then
        VAX_FOUND="true"
        VAX_NAME="Unidentified Vaccine Entry"
    fi
fi

# --- Check 4: Chemoprophylaxis Prescription ---
RX_RECORD=$(gnuhealth_db_query "
    SELECT po.id, pt.name
    FROM gnuhealth_prescription_order po
    JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
    JOIN gnuhealth_medicament med ON pol.medicament = med.id
    JOIN product_product pp ON med.name = pp.id
    JOIN product_template pt ON pp.template = pt.id
    WHERE po.patient = $TARGET_PATIENT_ID
      AND po.id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY po.id DESC LIMIT 1" 2>/dev/null | head -1)

RX_FOUND="false"
RX_DRUG_NAME="none"
if [ -n "$RX_RECORD" ]; then
    RX_FOUND="true"
    RX_DRUG_NAME=$(echo "$RX_RECORD" | awk -F'|' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi

# --- Check 5: Follow-up Appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="null"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi

# Get targeted patient name for sanity check
TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT pp.name, pp.lastname
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID LIMIT 1
" 2>/dev/null | tr '|' ' ')

# --- Build JSON result ---
TEMP_JSON=$(mktemp /tmp/travel_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_date": "$TASK_START_DATE",
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_patient_name": "$(json_escape "$TARGET_PATIENT_NAME")",
    
    "z_code_found": $Z_FOUND,
    "z_code": "$Z_CODE",
    "z_code_active": $Z_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    
    "evaluation_found": $EVAL_FOUND,
    "evaluation_systolic": "$EVAL_SYS",
    "evaluation_diastolic": "$EVAL_DIA",
    "evaluation_heart_rate": "$EVAL_HR",
    
    "vaccination_found": $VAX_FOUND,
    "vaccination_name": "$(json_escape "$VAX_NAME")",
    
    "prescription_found": $RX_FOUND,
    "prescription_drug_name": "$(json_escape "$RX_DRUG_NAME")",
    
    "appointment_found": $APPT_FOUND,
    "appointment_date": "$APPT_DATE"
}
EOF

# Move securely to the expected path
rm -f /tmp/occupational_travel_medicine_clearance_result.json 2>/dev/null || sudo rm -f /tmp/occupational_travel_medicine_clearance_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_travel_medicine_clearance_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/occupational_travel_medicine_clearance_result.json
chmod 666 /tmp/occupational_travel_medicine_clearance_result.json 2>/dev/null || sudo chmod 666 /tmp/occupational_travel_medicine_clearance_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/occupational_travel_medicine_clearance_result.json"
cat /tmp/occupational_travel_medicine_clearance_result.json
echo "=== Export Complete ==="