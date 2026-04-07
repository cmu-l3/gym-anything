#!/bin/bash
echo "=== Exporting occupational_shift_work_sleep_disorder result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/swsd_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/swsd_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/swsd_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/swsd_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/swsd_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_LIFESTYLE_MAX=$(cat /tmp/swsd_baseline_lifestyle_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/swsd_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/swsd_target_patient_id 2>/dev/null || echo "0")
TARGET_PARTY_ID=$(cat /tmp/swsd_target_party_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/swsd_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# Fetch Target Patient Name
TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,''))
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID" | sed 's/^[[:space:]]*//')

# --- Check 1: G47.x Sleep disorder diagnosis ---
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

# Determine if it's G47.2 (circadian rhythm) specifically
G472_SPECIFIC="false"
if [ "$G47_FOUND" = "true" ] && [[ "$G47_CODE" == G47.2* ]]; then
    G472_SPECIFIC="true"
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "G47 Diagnosis: found=$G47_FOUND code=$G47_CODE active=$G47_ACTIVE specific=$G472_SPECIFIC, any new: ${ANY_NEW_DISEASE:-0}"


# --- Check 2: Clinical evaluation ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(chief_complaint,''), COALESCE(present_illness,'')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_NOTES="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    # Combine chief complaint and present illness for text search
    CC=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}')
    PI=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}')
    EVAL_NOTES="${CC} ${PI}"
fi
echo "Evaluation: found=$EVAL_FOUND"


# --- Check 3: Laboratory orders (CBC, TSH) ---
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

NEW_LAB_NAMES=$(gnuhealth_db_query "
    SELECT ltt.name
    FROM gnuhealth_patient_lab_test glt
    JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
    WHERE glt.patient_id = $TARGET_PATIENT_ID
      AND glt.id > $BASELINE_LAB_MAX
" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
echo "New lab orders: ${NEW_LAB_COUNT:-0} (types: $NEW_LAB_TYPES)"


# --- Check 4: Prescription (Modafinil/Armodafinil/Melatonin) ---
PRESC_FOUND="false"
SWSD_DRUG_FOUND="false"
SWSD_DRUG_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    SWSD_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%modafinil%'
               OR LOWER(pt.name) LIKE '%armodafinil%'
               OR LOWER(pt.name) LIKE '%melatonin%'
               OR LOWER(pt.name) LIKE '%solriamfetol%'
               OR LOWER(pt.name) LIKE '%pitolisant%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$SWSD_CHECK" ]; then
        SWSD_DRUG_FOUND="true"
        SWSD_DRUG_NAME="$SWSD_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, SWSD Drug: $SWSD_DRUG_FOUND ($SWSD_DRUG_NAME)"


# --- Check 5: Lifestyle counseling ---
LIFESTYLE_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(info,'')
    FROM gnuhealth_patient_lifestyle
    WHERE (patient_lifestyle = $TARGET_PATIENT_ID OR patient = $TARGET_PATIENT_ID)
      AND id > $BASELINE_LIFESTYLE_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1)

LIFESTYLE_FOUND="false"
LIFESTYLE_INFO="none"
if [ -n "$LIFESTYLE_RECORD" ]; then
    LIFESTYLE_FOUND="true"
    LIFESTYLE_INFO=$(echo "$LIFESTYLE_RECORD" | awk -F'|' '{print $2}')
fi

ANY_NEW_LIFESTYLE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lifestyle
    WHERE (patient_lifestyle = $TARGET_PATIENT_ID OR patient = $TARGET_PATIENT_ID)
      AND id > $BASELINE_LIFESTYLE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Lifestyle record: found=$LIFESTYLE_FOUND, total_new=${ANY_NEW_LIFESTYLE:-0}"


# --- Check 6: Follow-up Appointment (14 to 30 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date, appointment_date::date - '$TASK_START_DATE'::date as days_diff
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="null"
APPT_DAYS_DIFF="0"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    APPT_DAYS_DIFF=$(echo "$APPT_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi

TOTAL_NEW_APPTS=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Appointment: found=$APPT_FOUND, days_diff=$APPT_DAYS_DIFF, total_new=${TOTAL_NEW_APPTS:-0}"


# Escaping JSON fields
EVAL_NOTES_ESC=$(echo "$EVAL_NOTES" | sed 's/"/\\"/g' | sed 's/\n/\\n/g')
LIFESTYLE_INFO_ESC=$(echo "$LIFESTYLE_INFO" | sed 's/"/\\"/g' | sed 's/\n/\\n/g')
TARGET_PATIENT_NAME_ESC=$(echo "$TARGET_PATIENT_NAME" | sed 's/"/\\"/g')

# --- Save JSON ---
TEMP_JSON=$(mktemp /tmp/swsd_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "$TARGET_PATIENT_NAME_ESC",
    "g47_found": $G47_FOUND,
    "g47_code": "$G47_CODE",
    "g47_active": $G47_ACTIVE,
    "g472_specific": $G472_SPECIFIC,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_notes": "$EVAL_NOTES_ESC",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "new_lab_names": "$NEW_LAB_NAMES",
    "prescription_found": $PRESC_FOUND,
    "swsd_drug_found": $SWSD_DRUG_FOUND,
    "swsd_drug_name": "$SWSD_DRUG_NAME",
    "lifestyle_found": $LIFESTYLE_FOUND,
    "lifestyle_info": "$LIFESTYLE_INFO_ESC",
    "any_new_lifestyle_count": ${ANY_NEW_LIFESTYLE:-0},
    "appt_found": $APPT_FOUND,
    "appt_date": "$APPT_DATE",
    "appt_days_diff": ${APPT_DAYS_DIFF:-0},
    "total_new_appts": ${TOTAL_NEW_APPTS:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/occupational_shift_work_sleep_disorder_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_shift_work_sleep_disorder_result.json
chmod 666 /tmp/occupational_shift_work_sleep_disorder_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="