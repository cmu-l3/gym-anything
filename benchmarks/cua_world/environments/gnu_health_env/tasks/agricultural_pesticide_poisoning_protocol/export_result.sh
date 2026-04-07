#!/bin/bash
echo "=== Exporting agricultural_pesticide_poisoning_protocol result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/pest_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/pest_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/pest_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/pest_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/pest_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/pest_baseline_appt_max 2>/dev/null || echo "0")
BASELINE_LAB_TYPE_MAX=$(cat /tmp/pest_baseline_lab_type_max 2>/dev/null || echo "0")
BASELINE_MEDICAMENT_MAX=$(cat /tmp/pest_baseline_medicament_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/pest_target_patient_id 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Custom Lab Creation and Order ---
LAB_TYPE_CREATED="false"
LAB_TYPE_NAME="none"
LAB_ORDERED_FOR_PATIENT="false"

CHOLIN_RECORD=$(gnuhealth_db_query "
    SELECT id, name, code FROM gnuhealth_lab_test_type 
    WHERE (UPPER(name) LIKE '%CHOLINESTERASE%' OR code = 'CHOLIN') 
      AND id > $BASELINE_LAB_TYPE_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null)

if [ -n "$CHOLIN_RECORD" ]; then
    LAB_TYPE_CREATED="true"
    CHOLIN_ID=$(echo "$CHOLIN_RECORD" | awk -F'|' '{print $1}' | tr -d ' ')
    LAB_TYPE_NAME=$(echo "$CHOLIN_RECORD" | awk -F'|' '{print $2}')
    
    # Check if this new lab was ordered for Roberto
    LAB_ORDER_CHECK=$(gnuhealth_db_query "
        SELECT COUNT(*) FROM gnuhealth_patient_lab_test 
        WHERE patient_id = $TARGET_PATIENT_ID 
          AND test_type = $CHOLIN_ID 
          AND id > $BASELINE_LAB_MAX" | tr -d '[:space:]')
          
    if [ "${LAB_ORDER_CHECK:-0}" -gt 0 ]; then
        LAB_ORDERED_FOR_PATIENT="true"
    fi
fi

# --- Check 2: Custom Medicament Creation and Prescription ---
MEDICAMENT_CREATED="false"
MEDICAMENT_NAME="none"
MEDICAMENT_PRESCRIBED_FOR_PATIENT="false"

ATROPINE_RECORD=$(gnuhealth_db_query "
    SELECT m.id, pt.name 
    FROM gnuhealth_medicament m 
    JOIN product_product pp ON m.name = pp.id 
    JOIN product_template pt ON pp.template = pt.id 
    WHERE UPPER(pt.name) LIKE '%ATROPINE%' 
      AND m.id > $BASELINE_MEDICAMENT_MAX 
    ORDER BY m.id DESC LIMIT 1" 2>/dev/null)

if [ -n "$ATROPINE_RECORD" ]; then
    MEDICAMENT_CREATED="true"
    ATROPINE_ID=$(echo "$ATROPINE_RECORD" | awk -F'|' '{print $1}' | tr -d ' ')
    MEDICAMENT_NAME=$(echo "$ATROPINE_RECORD" | awk -F'|' '{print $2}')
    
    # Check if this new medicament was prescribed to Roberto
    PRESC_CHECK=$(gnuhealth_db_query "
        SELECT COUNT(*) 
        FROM gnuhealth_prescription_order po 
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id 
        WHERE po.patient = $TARGET_PATIENT_ID 
          AND pol.medicament = $ATROPINE_ID 
          AND po.id > $BASELINE_PRESCRIPTION_MAX" | tr -d '[:space:]')
          
    if [ "${PRESC_CHECK:-0}" -gt 0 ]; then
        MEDICAMENT_PRESCRIBED_FOR_PATIENT="true"
    fi
fi

# --- Check 3: T60 Diagnosis ---
T60_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'T60%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

T60_FOUND="false"
T60_CODE="none"
T60_ACTIVE="false"
if [ -n "$T60_RECORD" ]; then
    T60_FOUND="true"
    T60_CODE=$(echo "$T60_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$T60_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        T60_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 4: Clinical Evaluation (Bradycardia <= 55) ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(heart_rate::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_HR="null"
EVAL_BRADYCARDIA="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    
    if echo "$EVAL_HR" | grep -qE '^[0-9]+$'; then
        BRADY_CHECK=$(echo "$EVAL_HR" | awk '{if ($1 <= 55) print "true"; else print "false"}')
        EVAL_BRADYCARDIA="${BRADY_CHECK:-false}"
    fi
fi

# --- Check 5: Follow-up Appointment (7-14 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, (appointment_date::date - CURRENT_DATE::date) AS days_out
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS_OUT="null"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DAYS_OUT=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi

# Prepare JSON
TEMP_JSON=$(mktemp /tmp/pest_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "lab_type_created": $LAB_TYPE_CREATED,
    "lab_type_name": "$(echo "$LAB_TYPE_NAME" | sed 's/"/\\"/g')",
    "lab_ordered_for_patient": $LAB_ORDERED_FOR_PATIENT,
    "medicament_created": $MEDICAMENT_CREATED,
    "medicament_name": "$(echo "$MEDICAMENT_NAME" | sed 's/"/\\"/g')",
    "medicament_prescribed": $MEDICAMENT_PRESCRIBED_FOR_PATIENT,
    "t60_diagnosis_found": $T60_FOUND,
    "t60_diagnosis_code": "$T60_CODE",
    "t60_diagnosis_active": $T60_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_heart_rate": "$EVAL_HR",
    "evaluation_bradycardia": $EVAL_BRADYCARDIA,
    "appointment_found": $APPT_FOUND,
    "appointment_days_out": "$APPT_DAYS_OUT"
}
EOF

# Ensure safe copy
rm -f /tmp/agricultural_pesticide_poisoning_protocol_result.json 2>/dev/null || sudo rm -f /tmp/agricultural_pesticide_poisoning_protocol_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/agricultural_pesticide_poisoning_protocol_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/agricultural_pesticide_poisoning_protocol_result.json
chmod 666 /tmp/agricultural_pesticide_poisoning_protocol_result.json 2>/dev/null || sudo chmod 666 /tmp/agricultural_pesticide_poisoning_protocol_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/agricultural_pesticide_poisoning_protocol_result.json