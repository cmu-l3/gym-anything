#!/bin/bash
echo "=== Exporting occupational_manganism_protocol result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/mang_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/mang_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/mang_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/mang_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/mang_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/mang_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/mang_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/mang_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT pp.name || ' ' || COALESCE(pp.lastname,'')
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID
    LIMIT 1" | xargs)

# --- Check 1: G21 or T56 diagnosis (new, active) ---
DISEASE_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'G21%' OR gpath.code LIKE 'T56%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

DISEASE_FOUND="false"
DISEASE_ACTIVE="false"
DISEASE_CODE="null"
if [ -n "$DISEASE_RECORD" ]; then
    DISEASE_FOUND="true"
    DISEASE_CODE=$(echo "$DISEASE_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$DISEASE_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        DISEASE_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Clinical evaluation ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(heart_rate::text,'null'),
           COALESCE(notes,'') || ' ' || COALESCE(chief_complaint,'')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_HR="null"
EVAL_HAS_TACHYCARDIA="false"
EVAL_HAS_NOTE="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_TEXT=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr '[A-Z]' '[a-z]')

    if echo "$EVAL_HR" | grep -qE '^[0-9]+$'; then
        TACHY_CHECK=$(echo "$EVAL_HR" | awk '{if ($1 >= 90) print "true"; else print "false"}')
        EVAL_HAS_TACHYCARDIA="${TACHY_CHECK:-false}"
    fi

    if echo "$EVAL_TEXT" | grep -qiE "bradykinesia|tremor|cock walk|parkinson"; then
        EVAL_HAS_NOTE="true"
    fi
fi

# --- Check 3: Labs (>= 2) ---
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

# --- Check 4: Levodopa prescription ---
PRESC_FOUND="false"
LEVODOPA_FOUND="false"
LEVODOPA_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    MED_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%levodopa%'
               OR LOWER(pt.name) LIKE '%carbidopa%'
               OR LOWER(pt.name) LIKE '%sinemet%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$MED_CHECK" ]; then
        LEVODOPA_FOUND="true"
        LEVODOPA_NAME="$MED_CHECK"
    fi
fi

# --- Check 5: Follow-up appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY appointment_date DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

APPT_FOUND="false"
APPT_DATE="none"
APPT_DAYS_DIFF=-1

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE="$APPT_RECORD"
    
    # Calculate days difference
    START_SEC=$(date -d "$TASK_START_DATE" +%s)
    APPT_SEC=$(date -d "$APPT_DATE" +%s 2>/dev/null || echo "$START_SEC")
    APPT_DAYS_DIFF=$(((APPT_SEC - START_SEC) / 86400))
fi

# Output JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": "$TARGET_PATIENT_ID",
    "target_patient_name": "$TARGET_PATIENT_NAME",
    "disease_found": $DISEASE_FOUND,
    "disease_code": "$DISEASE_CODE",
    "disease_active": $DISEASE_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "evaluation_found": $EVAL_FOUND,
    "evaluation_heart_rate": "$EVAL_HR",
    "evaluation_has_tachycardia": $EVAL_HAS_TACHYCARDIA,
    "evaluation_has_note": $EVAL_HAS_NOTE,
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "prescription_found": $PRESC_FOUND,
    "levodopa_found": $LEVODOPA_FOUND,
    "levodopa_name": "$LEVODOPA_NAME",
    "appointment_found": $APPT_FOUND,
    "appointment_date": "$APPT_DATE",
    "appointment_days_diff": $APPT_DAYS_DIFF
}
EOF

rm -f /tmp/occupational_manganism_protocol_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_manganism_protocol_result.json 2>/dev/null
chmod 666 /tmp/occupational_manganism_protocol_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export Complete."
cat /tmp/occupational_manganism_protocol_result.json