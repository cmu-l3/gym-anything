#!/bin/bash
echo "=== Exporting occupational_acute_mountain_sickness result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/ams_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/ams_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/ams_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/ams_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/ams_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/ams_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/ams_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/ams_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: T70.x Diagnosis ---
T70_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'T70%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

T70_FOUND="false"
T70_ACTIVE="false"
T70_CODE="null"
if [ -n "$T70_RECORD" ]; then
    T70_FOUND="true"
    T70_CODE=$(echo "$T70_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$T70_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        T70_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "T70.x Diagnosis: found=$T70_FOUND code=$T70_CODE active=$T70_ACTIVE, any new disease: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Clinical evaluation with Hypoxia & Tachycardia ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(osat::text,'null'), COALESCE(heart_rate::text,'null'),
           COALESCE(chief_complaint,'')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_OSAT="null"
EVAL_HR="null"
EVAL_HAS_HYPOXIA="false"
EVAL_HAS_TACHYCARDIA="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_OSAT=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')

    if echo "$EVAL_OSAT" | grep -qE '^[0-9]+$'; then
        HYPOXIA_CHECK=$(echo "$EVAL_OSAT" | awk '{if ($1 <= 88) print "true"; else print "false"}')
        EVAL_HAS_HYPOXIA="${HYPOXIA_CHECK:-false}"
    fi

    if echo "$EVAL_HR" | grep -qE '^[0-9]+$'; then
        TACHY_CHECK=$(echo "$EVAL_HR" | awk '{if ($1 >= 100) print "true"; else print "false"}')
        EVAL_HAS_TACHYCARDIA="${TACHY_CHECK:-false}"
    fi
fi
echo "Evaluation: found=$EVAL_FOUND, osat=$EVAL_OSAT (hypoxia=$EVAL_HAS_HYPOXIA), HR=$EVAL_HR (tachy=$EVAL_HAS_TACHYCARDIA)"

# --- Check 3: AMS Prescription (Acetazolamide/Dexamethasone) ---
PRESC_FOUND="false"
AMS_RX_FOUND="false"
AMS_DRUG_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    ABX_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%acetazolamid%'
               OR LOWER(pt.name) LIKE '%dexamethason%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$ABX_CHECK" ]; then
        AMS_RX_FOUND="true"
        AMS_DRUG_NAME="$ABX_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, AMS Rx: $AMS_RX_FOUND ($AMS_DRUG_NAME)"

# --- Check 4: Lab Order (Blood Gas, ABG, Metabolic) ---
LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $TARGET_PATIENT_ID
      AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')

TARGET_LAB_FOUND="false"
TARGET_LAB_NAME="none"
if [ "${LAB_COUNT:-0}" -gt 0 ]; then
    LAB_CHECK=$(gnuhealth_db_query "
        SELECT ltt.name
        FROM gnuhealth_patient_lab_test glt
        JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
        WHERE glt.patient_id = $TARGET_PATIENT_ID
          AND glt.id > $BASELINE_LAB_MAX
          AND (LOWER(ltt.name) LIKE '%gas%'
               OR LOWER(ltt.code) LIKE '%abg%'
               OR LOWER(ltt.name) LIKE '%metabolic%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')
    if [ -n "$LAB_CHECK" ]; then
        TARGET_LAB_FOUND="true"
        TARGET_LAB_NAME="$LAB_CHECK"
    fi
fi
echo "Lab Orders count: $LAB_COUNT, Target lab: $TARGET_LAB_FOUND ($TARGET_LAB_NAME)"

# --- Check 5: Follow-up Appointment (1-3 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="none"
DAYS_DIFF="-999"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    
    # Calculate days difference from task start date
    if [ -n "$APPT_DATE" ] && [ "$APPT_DATE" != "none" ]; then
        START_TS=$(date -d "$TASK_START_DATE" +%s 2>/dev/null || date +%s)
        APPT_TS=$(date -d "$APPT_DATE" +%s 2>/dev/null || echo "0")
        if [ "$APPT_TS" -gt 0 ]; then
            DAYS_DIFF=$(((APPT_TS - START_TS) / 86400))
        fi
    fi
fi
echo "Appointment: found=$APPT_FOUND date=$APPT_DATE days_diff=$DAYS_DIFF"

# --- Get Patient Name for safety ---
TARGET_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID
    LIMIT 1" 2>/dev/null | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Export JSON
TEMP_JSON=$(mktemp /tmp/ams_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "$(json_escape "$TARGET_NAME")",
    "t70_found": $T70_FOUND,
    "t70_active": $T70_ACTIVE,
    "t70_code": "$(json_escape "$T70_CODE")",
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_has_hypoxia": $EVAL_HAS_HYPOXIA,
    "evaluation_has_tachycardia": $EVAL_HAS_TACHYCARDIA,
    "evaluation_osat": "$(json_escape "$EVAL_OSAT")",
    "evaluation_heart_rate": "$(json_escape "$EVAL_HR")",
    "prescription_found": $PRESC_FOUND,
    "ams_rx_found": $AMS_RX_FOUND,
    "ams_drug_name": "$(json_escape "$AMS_DRUG_NAME")",
    "lab_count": ${LAB_COUNT:-0},
    "target_lab_found": $TARGET_LAB_FOUND,
    "target_lab_name": "$(json_escape "$TARGET_LAB_NAME")",
    "appt_found": $APPT_FOUND,
    "appt_date": "$(json_escape "$APPT_DATE")",
    "appt_days_diff": $DAYS_DIFF,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result /tmp/occupational_acute_mountain_sickness_result.json "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/occupational_acute_mountain_sickness_result.json
echo ""
echo "=== Export Complete ==="