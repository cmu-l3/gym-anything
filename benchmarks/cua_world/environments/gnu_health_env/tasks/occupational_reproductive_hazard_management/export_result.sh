#!/bin/bash
echo "=== Exporting occupational_reproductive_hazard_management result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga
sleep 1

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/repro_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_PRESC_MAX=$(cat /tmp/repro_baseline_presc_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/repro_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_LIFESTYLE_MAX=$(cat /tmp/repro_baseline_lifestyle_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/repro_target_patient_id 2>/dev/null || echo "0")

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Pregnancy Diagnosis ---
PREG_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'O09%' OR gpath.code LIKE 'Z33%' OR gpath.code LIKE 'Z34%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

PREG_FOUND="false"
PREG_CODE="null"
PREG_ACTIVE="false"
if [ -n "$PREG_RECORD" ]; then
    PREG_FOUND="true"
    PREG_CODE=$(echo "$PREG_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$PREG_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        PREG_ACTIVE="true"
    fi
fi

# --- Check 2: Hazard Diagnosis (Z57) ---
HAZARD_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'Z57%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

HAZARD_FOUND="false"
HAZARD_CODE="null"
HAZARD_ACTIVE="false"
if [ -n "$HAZARD_RECORD" ]; then
    HAZARD_FOUND="true"
    HAZARD_CODE=$(echo "$HAZARD_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$HAZARD_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        HAZARD_ACTIVE="true"
    fi
fi

# --- Check 3: Prenatal Prescription ---
PRESC_FOUND="false"
PRENATAL_FOUND="false"
PRENATAL_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_PRESC_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"
    PRENATAL_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESC_MAX
          AND (LOWER(pt.name) LIKE '%folic%'
               OR LOWER(pt.name) LIKE '%vitamin%'
               OR LOWER(pt.name) LIKE '%iron%'
               OR LOWER(pt.name) LIKE '%ferrous%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$PRENATAL_CHECK" ]; then
        PRENATAL_FOUND="true"
        PRENATAL_NAME="$PRENATAL_CHECK"
    fi
fi

# --- Check 4: Work Restriction Lifestyle Note ---
LIFESTYLE_INFO=$(gnuhealth_db_query "
    SELECT info
    FROM gnuhealth_patient_lifestyle
    WHERE (patient = $TARGET_PATIENT_ID OR patient_lifestyle = $TARGET_PATIENT_ID)
      AND id > $BASELINE_LIFESTYLE_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1 | tr -d '\n' | sed 's/"/\\"/g')

LIFESTYLE_FOUND="false"
RESTRICTION_KEYWORDS_FOUND="false"
if [ -n "$LIFESTYLE_INFO" ]; then
    LIFESTYLE_FOUND="true"
    LOWER_INFO=$(echo "$LIFESTYLE_INFO" | tr '[:upper:]' '[:lower:]')
    if [[ "$LOWER_INFO" == *"restrict"* ]] || [[ "$LOWER_INFO" == *"reassign"* ]] || [[ "$LOWER_INFO" == *"teratogen"* ]] || [[ "$LOWER_INFO" == *"hazard"* ]]; then
        RESTRICTION_KEYWORDS_FOUND="true"
    fi
fi

# --- Check 5: Baseline Labs ---
NEW_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $TARGET_PATIENT_ID AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')

NEW_LAB_TYPES=$(gnuhealth_db_query "
    SELECT ltt.code
    FROM gnuhealth_patient_lab_test glt
    JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
    WHERE glt.patient_id = $TARGET_PATIENT_ID AND glt.id > $BASELINE_LAB_MAX
    ORDER BY glt.id
" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# --- Check 6: Process Info ---
FIREFOX_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "firefox_was_running": $FIREFOX_RUNNING,
    "target_patient_id": "$TARGET_PATIENT_ID",
    "preg_found": $PREG_FOUND,
    "preg_code": "$PREG_CODE",
    "preg_active": $PREG_ACTIVE,
    "hazard_found": $HAZARD_FOUND,
    "hazard_code": "$HAZARD_CODE",
    "hazard_active": $HAZARD_ACTIVE,
    "presc_found": $PRESC_FOUND,
    "prenatal_found": $PRENATAL_FOUND,
    "prenatal_name": "$PRENATAL_NAME",
    "lifestyle_found": $LIFESTYLE_FOUND,
    "restriction_keywords_found": $RESTRICTION_KEYWORDS_FOUND,
    "lifestyle_info": "$LIFESTYLE_INFO",
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES"
}
EOF

rm -f /tmp/occupational_reproductive_hazard_management_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_reproductive_hazard_management_result.json
chmod 666 /tmp/occupational_reproductive_hazard_management_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/occupational_reproductive_hazard_management_result.json"
cat /tmp/occupational_reproductive_hazard_management_result.json
echo "=== Export complete ==="