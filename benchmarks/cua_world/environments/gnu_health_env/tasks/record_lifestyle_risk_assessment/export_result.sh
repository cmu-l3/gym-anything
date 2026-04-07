#!/bin/bash
echo "=== Exporting record_lifestyle_risk_assessment result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/lfa_final_state.png ga

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/lfa_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/lfa_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/lfa_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/lfa_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/lfa_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/lfa_task_start_date 2>/dev/null || date +%Y-%m-%d)
TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || date +%s)

echo "Target patient_id: $TARGET_PATIENT_ID"

# Fetch Target Patient Name (for verifier cross-check)
TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID
    LIMIT 1" | sed 's/^[[:space:]]*//')

# --- Check 1: Lifestyle Fields (on gnuhealth_patient record) ---
LIFESTYLE_RECORD=$(gnuhealth_db_query "
    SELECT COALESCE(smoking::text, 'false'), 
           COALESCE(smoking_number::text, '0'), 
           COALESCE(exercise::text, 'false'), 
           COALESCE(alcohol::text, 'false'), 
           COALESCE(sleep_hours::text, '0')
    FROM gnuhealth_patient
    WHERE id = $TARGET_PATIENT_ID
" 2>/dev/null)

LF_SMOKING=$(echo "$LIFESTYLE_RECORD" | awk -F'|' '{print $1}' | tr -d ' ')
LF_SMOKING_NUM=$(echo "$LIFESTYLE_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
LF_EXERCISE=$(echo "$LIFESTYLE_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
LF_ALCOHOL=$(echo "$LIFESTYLE_RECORD" | awk -F'|' '{print $4}' | tr -d ' ')
LF_SLEEP=$(echo "$LIFESTYLE_RECORD" | awk -F'|' '{print $5}' | tr -d ' ')

echo "Lifestyle -> Smoking: $LF_SMOKING ($LF_SMOKING_NUM/day), Exercise: $LF_EXERCISE, Alcohol: $LF_ALCOHOL, Sleep: $LF_SLEEP"

# --- Check 2: F17.x Tobacco Use Disorder Diagnosis ---
F17_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'F17%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

F17_FOUND="false"
F17_ACTIVE="false"
F17_CODE="null"
if [ -n "$F17_RECORD" ]; then
    F17_FOUND="true"
    F17_CODE=$(echo "$F17_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$F17_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        F17_ACTIVE="true"
    fi
fi

# General new disease count
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 3: Cessation Prescription ---
PRESC_FOUND="false"
CESSATION_FOUND="false"
CESSATION_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    CESSATION_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%nicotine%'
               OR LOWER(pt.name) LIKE '%varenicline%'
               OR LOWER(pt.name) LIKE '%bupropion%'
               OR LOWER(pt.name) LIKE '%champix%'
               OR LOWER(pt.name) LIKE '%chantix%'
               OR LOWER(pt.name) LIKE '%zyban%'
               OR LOWER(pt.name) LIKE '%wellbutrin%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$CESSATION_CHECK" ]; then
        CESSATION_FOUND="true"
        CESSATION_NAME="$CESSATION_CHECK"
    fi
fi

# --- Check 4: Baseline Labs (>= 2) ---
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

# --- Check 5: Follow-up Appointment ---
NEW_APPT_DATE=$(gnuhealth_db_query "
    SELECT appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | tr -d '[:space:]')

APPT_FOUND="false"
if [ -n "$NEW_APPT_DATE" ]; then
    APPT_FOUND="true"
fi

# --- Export JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "$(json_escape "$TARGET_PATIENT_NAME")",
    "lifestyle": {
        "smoking": "$LF_SMOKING",
        "smoking_number": "$LF_SMOKING_NUM",
        "exercise": "$LF_EXERCISE",
        "alcohol": "$LF_ALCOHOL",
        "sleep_hours": "$LF_SLEEP"
    },
    "f17_found": $F17_FOUND,
    "f17_active": $F17_ACTIVE,
    "f17_code": "$F17_CODE",
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "prescription_found": $PRESC_FOUND,
    "cessation_found": $CESSATION_FOUND,
    "cessation_drug_name": "$(json_escape "$CESSATION_NAME")",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "appt_found": $APPT_FOUND,
    "appt_date": "$NEW_APPT_DATE",
    "task_start_date": "$TASK_START_DATE",
    "task_start_time": $TASK_START_TIME,
    "export_time": $(date +%s),
    "screenshot_path": "/tmp/lfa_final_state.png"
}
EOF

rm -f /tmp/record_lifestyle_risk_assessment_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/record_lifestyle_risk_assessment_result.json 2>/dev/null
chmod 666 /tmp/record_lifestyle_risk_assessment_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/record_lifestyle_risk_assessment_result.json
echo "=== Export Complete ==="