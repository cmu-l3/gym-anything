#!/bin/bash
echo "=== Exporting commercial_driver_fitness_exam result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/fitness_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/fitness_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/fitness_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/fitness_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/fitness_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/fitness_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/fitness_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Clinical evaluation with elevated BP ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(systolic::text,'null'), COALESCE(diastolic::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_SYS="null"
EVAL_DIA="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_SYS=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_DIA=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi
echo "Evaluation: found=$EVAL_FOUND, sys=$EVAL_SYS, dia=$EVAL_DIA"

# --- Check 2: I10 Hypertension Diagnosis ---
I10_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'I10%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

I10_FOUND="false"
I10_CODE="null"
I10_ACTIVE="false"
if [ -n "$I10_RECORD" ]; then
    I10_FOUND="true"
    I10_CODE=$(echo "$I10_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$I10_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        I10_ACTIVE="true"
    fi
fi

# --- Check 3: G47 Sleep Apnea Diagnosis ---
G47_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'G47%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

G47_FOUND="false"
G47_CODE="null"
G47_ACTIVE="false"
if [ -n "$G47_RECORD" ]; then
    G47_FOUND="true"
    G47_CODE=$(echo "$G47_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$G47_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        G47_ACTIVE="true"
    fi
fi
echo "Diagnoses: I10_found=$I10_FOUND, G47_found=$G47_FOUND"

# --- Check 4: Antihypertensive Prescription ---
PRESC_FOUND="false"
DRUG_NAME="none"

NEW_PRESC=$(gnuhealth_db_query "
    SELECT pt.name
    FROM gnuhealth_prescription_order po
    JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
    JOIN gnuhealth_medicament med ON pol.medicament = med.id
    JOIN product_product pp ON med.name = pp.id
    JOIN product_template pt ON pp.template = pt.id
    WHERE po.patient = $TARGET_PATIENT_ID
      AND po.id > $BASELINE_PRESCRIPTION_MAX
      AND (LOWER(pt.name) LIKE '%amlodipin%'
           OR LOWER(pt.name) LIKE '%lisinopril%'
           OR LOWER(pt.name) LIKE '%losartan%')
    LIMIT 1
" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

if [ -n "$NEW_PRESC" ]; then
    PRESC_FOUND="true"
    DRUG_NAME="$NEW_PRESC"
fi
echo "Prescription: found=$PRESC_FOUND ($DRUG_NAME)"

# --- Check 5: Reassessment Appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="null"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE="$APPT_RECORD"
fi
echo "Appointment: found=$APPT_FOUND (date=$APPT_DATE)"

# --- Compile JSON ---
TEMP_JSON=$(mktemp /tmp/commercial_driver_fitness_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "John Zenon",
    "eval_found": $EVAL_FOUND,
    "eval_sys": "$EVAL_SYS",
    "eval_dia": "$EVAL_DIA",
    "i10_found": $I10_FOUND,
    "i10_code": "$I10_CODE",
    "i10_active": $I10_ACTIVE,
    "g47_found": $G47_FOUND,
    "g47_code": "$G47_CODE",
    "g47_active": $G47_ACTIVE,
    "prescription_found": $PRESC_FOUND,
    "drug_name": "$(json_escape "$DRUG_NAME")",
    "appt_found": $APPT_FOUND,
    "appt_date": "$(json_escape "$APPT_DATE")",
    "task_start_date": "$TASK_START_DATE"
}
EOF

# Save JSON safely
rm -f /tmp/commercial_driver_fitness_result.json 2>/dev/null || sudo rm -f /tmp/commercial_driver_fitness_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/commercial_driver_fitness_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/commercial_driver_fitness_result.json
chmod 666 /tmp/commercial_driver_fitness_result.json 2>/dev/null || sudo chmod 666 /tmp/commercial_driver_fitness_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/commercial_driver_fitness_result.json"
cat /tmp/commercial_driver_fitness_result.json
echo "=== Export Complete ==="