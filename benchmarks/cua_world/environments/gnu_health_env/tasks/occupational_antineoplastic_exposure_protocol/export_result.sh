#!/bin/bash
echo "=== Exporting occupational_antineoplastic_exposure_protocol result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/antineo_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/antineo_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/antineo_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/antineo_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/antineo_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/antineo_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/antineo_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/antineo_task_start_date 2>/dev/null || date +%Y-%m-%d)

TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID LIMIT 1" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

echo "Target patient_id: $TARGET_PATIENT_ID ($TARGET_PATIENT_NAME)"

# --- Check 1: Exposure Diagnosis (Z57 or T45) ---
DISEASE_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'Z57%' OR gpath.code LIKE 'T45%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

EXP_FOUND="false"
EXP_ACTIVE="false"
EXP_CODE="null"
EXP_SPECIFIC="false"

if [ -n "$DISEASE_RECORD" ]; then
    EXP_FOUND="true"
    EXP_CODE=$(echo "$DISEASE_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$DISEASE_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        EXP_ACTIVE="true"
    fi
    case "$EXP_CODE" in
        Z57.5*|T45.1*) EXP_SPECIFIC="true" ;;
    esac
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient_disease WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX" 2>/dev/null | tr -d '[:space:]')
echo "Diagnosis: found=$EXP_FOUND code=$EXP_CODE active=$EXP_ACTIVE specific=$EXP_SPECIFIC"

# --- Check 2: Clinical Evaluation ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(temperature::text,'null'), COALESCE(heart_rate::text,'null'), COALESCE(systolic::text,'null'), COALESCE(diastolic::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_TEMP="null"
EVAL_HR="null"
EVAL_SYS="null"
EVAL_DIA="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_TEMP=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    EVAL_SYS=$(echo "$EVAL_RECORD" | awk -F'|' '{print $4}' | tr -d ' ')
    EVAL_DIA=$(echo "$EVAL_RECORD" | awk -F'|' '{print $5}' | tr -d ' ')
fi
echo "Evaluation: found=$EVAL_FOUND temp=$EVAL_TEMP hr=$EVAL_HR sys=$EVAL_SYS dia=$EVAL_DIA"

# --- Check 3: Laboratory Orders ---
NEW_LAB_COUNT=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient_lab_test WHERE patient_id = $TARGET_PATIENT_ID AND id > $BASELINE_LAB_MAX" 2>/dev/null | tr -d '[:space:]')
NEW_LAB_TYPES=$(gnuhealth_db_query "
    SELECT ltt.code
    FROM gnuhealth_patient_lab_test glt
    JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
    WHERE glt.patient_id = $TARGET_PATIENT_ID AND glt.id > $BASELINE_LAB_MAX
    ORDER BY glt.id
" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
echo "New lab orders: ${NEW_LAB_COUNT:-0} (types: $NEW_LAB_TYPES)"

# --- Check 4: Prescription ---
PRESC_FOUND="false"
CORTICOSTEROID_FOUND="false"
CORTICOSTEROID_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_prescription_order WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_PRESCRIPTION_MAX ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"
    DRUG_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%hydrocortisone%' OR LOWER(pt.name) LIKE '%cortisone%' 
               OR LOWER(pt.name) LIKE '%dexamethasone%' OR LOWER(pt.name) LIKE '%betamethasone%' 
               OR LOWER(pt.name) LIKE '%triamcinolone%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$DRUG_CHECK" ]; then
        CORTICOSTEROID_FOUND="true"
        CORTICOSTEROID_NAME="$DRUG_CHECK"
    fi
fi
echo "Prescription: found=$PRESC_FOUND corticosteroid=$CORTICOSTEROID_FOUND ($CORTICOSTEROID_NAME)"

# --- Check 5: Appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="null"
APPT_DAYS_DIFF=0

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    if [ -n "$APPT_DATE" ] && [ "$APPT_DATE" != "null" ]; then
        TODAY_SEC=$(date -d "$TASK_START_DATE" +%s 2>/dev/null || date +%s)
        APPT_SEC=$(date -d "$APPT_DATE" +%s 2>/dev/null || echo "0")
        if [ "$APPT_SEC" -gt 0 ]; then
            APPT_DAYS_DIFF=$(( (APPT_SEC - TODAY_SEC) / 86400 ))
        fi
    fi
fi
echo "Appointment: found=$APPT_FOUND date=$APPT_DATE days_diff=$APPT_DAYS_DIFF"

# JSON export
TEMP_JSON=$(mktemp /tmp/antineo_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "$(json_escape "$TARGET_PATIENT_NAME")",
    
    "exp_found": $EXP_FOUND,
    "exp_active": $EXP_ACTIVE,
    "exp_code": "$EXP_CODE",
    "exp_specific": $EXP_SPECIFIC,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    
    "eval_found": $EVAL_FOUND,
    "eval_temp": "$EVAL_TEMP",
    "eval_hr": "$EVAL_HR",
    "eval_sys": "$EVAL_SYS",
    "eval_dia": "$EVAL_DIA",
    
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    
    "prescription_found": $PRESC_FOUND,
    "corticosteroid_found": $CORTICOSTEROID_FOUND,
    "corticosteroid_name": "$(json_escape "$CORTICOSTEROID_NAME")",
    
    "appt_found": $APPT_FOUND,
    "appt_date": "$APPT_DATE",
    "appt_days_diff": $APPT_DAYS_DIFF
}
EOF

rm -f /tmp/occupational_antineoplastic_exposure_protocol_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_antineoplastic_exposure_protocol_result.json 2>/dev/null || true
chmod 666 /tmp/occupational_antineoplastic_exposure_protocol_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="