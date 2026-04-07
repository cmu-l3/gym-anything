#!/bin/bash
echo "=== Exporting record_occupational_rads result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/rads_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/rads_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/rads_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/rads_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/rads_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/rads_target_patient_id 2>/dev/null || echo "0")
TODAY=$(date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: J68.x RADS / Toxic Inhalation diagnosis ---
J68_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'J68%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

J68_FOUND="false"
J68_CODE="null"
J68_ACTIVE="false"
if [ -n "$J68_RECORD" ]; then
    J68_FOUND="true"
    J68_CODE=$(echo "$J68_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$J68_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        J68_ACTIVE="true"
    fi
fi

# Fallback: any J-code (Respiratory)
ANY_JCODE_FOUND="false"
ANY_JCODE=$(gnuhealth_db_query "
    SELECT gpath.code
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'J%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')
if [ -n "$ANY_JCODE" ]; then ANY_JCODE_FOUND="true"; fi

# --- Check 2: Clinical evaluation with specific vitals ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, 
           COALESCE(heart_rate::text,'null'),
           COALESCE(temperature::text,'null'),
           COALESCE(respiratory_rate::text,'null'),
           COALESCE(systolic::text,'null')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_HR="null"
EVAL_TEMP="null"
EVAL_RR="null"
EVAL_SYS="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_TEMP=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    EVAL_RR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $4}' | tr -d ' ')
    EVAL_SYS=$(echo "$EVAL_RECORD" | awk -F'|' '{print $5}' | tr -d ' ')
fi

# --- Check 3: Dual Pharmacotherapy ---
BRONCHO_FOUND="false"
BRONCHO_NAME="none"
BRONCHO_CHECK=$(gnuhealth_db_query "
    SELECT pt.name
    FROM gnuhealth_prescription_order po
    JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
    JOIN gnuhealth_medicament med ON pol.medicament = med.id
    JOIN product_product pp ON med.name = pp.id
    JOIN product_template pt ON pp.template = pt.id
    WHERE po.patient = $TARGET_PATIENT_ID
      AND po.id > $BASELINE_PRESCRIPTION_MAX
      AND (LOWER(pt.name) LIKE '%salbutamol%'
           OR LOWER(pt.name) LIKE '%albuterol%'
           OR LOWER(pt.name) LIKE '%ipratropium%'
           OR LOWER(pt.name) LIKE '%terbutaline%'
           OR LOWER(pt.name) LIKE '%formoterol%'
           OR LOWER(pt.name) LIKE '%salmeterol%')
    LIMIT 1
" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')
if [ -n "$BRONCHO_CHECK" ]; then BRONCHO_FOUND="true"; BRONCHO_NAME="$BRONCHO_CHECK"; fi

STEROID_FOUND="false"
STEROID_NAME="none"
STEROID_CHECK=$(gnuhealth_db_query "
    SELECT pt.name
    FROM gnuhealth_prescription_order po
    JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
    JOIN gnuhealth_medicament med ON pol.medicament = med.id
    JOIN product_product pp ON med.name = pp.id
    JOIN product_template pt ON pp.template = pt.id
    WHERE po.patient = $TARGET_PATIENT_ID
      AND po.id > $BASELINE_PRESCRIPTION_MAX
      AND (LOWER(pt.name) LIKE '%predniso%'
           OR LOWER(pt.name) LIKE '%methylpredni%'
           OR LOWER(pt.name) LIKE '%dexamethason%'
           OR LOWER(pt.name) LIKE '%budesonid%'
           OR LOWER(pt.name) LIKE '%fluticason%')
    LIMIT 1
" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')
if [ -n "$STEROID_CHECK" ]; then STEROID_FOUND="true"; STEROID_NAME="$STEROID_CHECK"; fi

# --- Check 4: Laboratory Orders ---
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
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE_STR="null"
DAYS_DIFF="0"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE_STR=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    
    # Calculate days difference using PostgreSQL to ensure date math is safe
    DAYS_DIFF=$(gnuhealth_db_query "SELECT DATE '$APPT_DATE_STR' - DATE '$TODAY'" 2>/dev/null | tr -d '[:space:]')
fi

# Construct Result JSON
TEMP_JSON=$(mktemp /tmp/rads_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "j68_found": $J68_FOUND,
    "j68_code": "$J68_CODE",
    "j68_active": $J68_ACTIVE,
    "any_jcode_found": $ANY_JCODE_FOUND,
    "any_jcode": "$ANY_JCODE",
    
    "eval_found": $EVAL_FOUND,
    "eval_hr": "$EVAL_HR",
    "eval_temp": "$EVAL_TEMP",
    "eval_rr": "$EVAL_RR",
    "eval_sys": "$EVAL_SYS",
    
    "broncho_found": $BRONCHO_FOUND,
    "broncho_name": "$BRONCHO_NAME",
    "steroid_found": $STEROID_FOUND,
    "steroid_name": "$STEROID_NAME",
    
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    
    "appt_found": $APPT_FOUND,
    "appt_date": "$APPT_DATE_STR",
    "appt_days_diff": ${DAYS_DIFF:-0}
}
EOF

rm -f /tmp/record_occupational_rads_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/record_occupational_rads_result.json
chmod 666 /tmp/record_occupational_rads_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="