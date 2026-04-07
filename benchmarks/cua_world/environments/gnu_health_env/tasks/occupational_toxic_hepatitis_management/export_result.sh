#!/bin/bash
echo "=== Exporting occupational_toxic_hepatitis_management result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/hep_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/hep_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_ALLERGY_MAX=$(cat /tmp/hep_baseline_allergy_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/hep_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/hep_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/hep_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/hep_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/hep_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

TARGET_PATIENT_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', COALESCE(pp.lastname,'')) 
    FROM gnuhealth_patient gp 
    JOIN party_party pp ON gp.party = pp.id 
    WHERE gp.id = $TARGET_PATIENT_ID" | sed 's/^[ \t]*//;s/[ \t]*$//')

# --- Check 1: K71.x Toxic Liver Disease diagnosis (new, active) ---
K71_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text 
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'K71%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

K71_FOUND="false"
K71_CODE="null"
K71_ACTIVE="false"
if [ -n "$K71_RECORD" ]; then
    K71_FOUND="true"
    K71_CODE=$(echo "$K71_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$K71_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        K71_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease 
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "K71 diagnosis: found=$K71_FOUND code=$K71_CODE active=$K71_ACTIVE, any new: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Solvent Adverse Reaction / Allergy ---
ALLERGY_RECORD=$(gnuhealth_db_query "
    SELECT id, allergen
    FROM gnuhealth_patient_allergy
    WHERE patient = $TARGET_PATIENT_ID
      AND (LOWER(allergen) LIKE '%toluene%' 
           OR LOWER(allergen) LIKE '%carbon tetrachloride%' 
           OR LOWER(allergen) LIKE '%solvent%'
           OR LOWER(allergen) LIKE '%degreaser%')
      AND id > $BASELINE_ALLERGY_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

ALLERGY_FOUND="false"
ALLERGY_NAME="none"
if [ -n "$ALLERGY_RECORD" ]; then
    ALLERGY_FOUND="true"
    ALLERGY_NAME=$(echo "$ALLERGY_RECORD" | awk -F'|' '{print $2}')
    ALLERGY_NAME=$(json_escape "$ALLERGY_NAME")
fi

ANY_NEW_ALLERGY=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_allergy
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_ALLERGY_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Solvent Allergy: found=$ALLERGY_FOUND name='$ALLERGY_NAME', any new: ${ANY_NEW_ALLERGY:-0}"

# --- Check 3: Hepatic monitoring labs (>= 3) ---
NEW_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $TARGET_PATIENT_ID
      AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')

NEW_LAB_TYPES=$(gnuhealth_db_query "
    SELECT ltt.name
    FROM gnuhealth_patient_lab_test glt
    JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
    WHERE glt.patient_id = $TARGET_PATIENT_ID
      AND glt.id > $BASELINE_LAB_MAX
    ORDER BY glt.id
" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
NEW_LAB_TYPES=$(json_escape "$NEW_LAB_TYPES")
echo "New lab orders: ${NEW_LAB_COUNT:-0} (types: $NEW_LAB_TYPES)"

# --- Check 4: Antiemetic prescription (Ondansetron etc) ---
PRESC_FOUND="false"
ANTIEMETIC_FOUND="false"
ANTIEMETIC_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"
    
    ANTIEMETIC_CHECK=$(gnuhealth_db_query "
        SELECT pt.name 
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%ondansetron%' 
               OR LOWER(pt.name) LIKE '%promethazine%'
               OR LOWER(pt.name) LIKE '%metoclopramide%'
               OR LOWER(pt.name) LIKE '%prochlorperazine%'
               OR LOWER(pt.name) LIKE '%antiemetic%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')
    
    if [ -n "$ANTIEMETIC_CHECK" ]; then
        ANTIEMETIC_FOUND="true"
        ANTIEMETIC_NAME=$(json_escape "$ANTIEMETIC_CHECK")
    fi
fi
echo "Prescription found: $PRESC_FOUND, Antiemetic: $ANTIEMETIC_FOUND ($ANTIEMETIC_NAME)"

# --- Check 5: Follow-up appointment ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date,
           (appointment_date::date - '$TASK_START_DATE'::date) as days_diff
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS_DIFF="0"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DAYS_DIFF=$(echo "$APPT_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi
echo "Appointment: found=$APPT_FOUND, days from today=$APPT_DAYS_DIFF"

# --- Generate JSON Result ---
TEMP_JSON=$(mktemp /tmp/occupational_toxic_hepatitis_management_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "$TARGET_PATIENT_NAME",
    "k71_found": $K71_FOUND,
    "k71_code": "$K71_CODE",
    "k71_active": $K71_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "solvent_allergy_found": $ALLERGY_FOUND,
    "solvent_allergy_name": "$ALLERGY_NAME",
    "any_new_allergy_count": ${ANY_NEW_ALLERGY:-0},
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "prescription_found": $PRESC_FOUND,
    "antiemetic_found": $ANTIEMETIC_FOUND,
    "antiemetic_name": "$ANTIEMETIC_NAME",
    "appt_found": $APPT_FOUND,
    "appt_days_diff": ${APPT_DAYS_DIFF:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result /tmp/occupational_toxic_hepatitis_management_result.json "$(cat "$TEMP_JSON")"

echo "=== Export Complete ==="