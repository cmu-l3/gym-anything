#!/bin/bash
echo "=== Exporting record_domiciliary_unit result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/du_final_state.png

# Load baselines
BASELINE_DU_MAX=$(cat /tmp/du_baseline_max 2>/dev/null || echo "0")
BASELINE_DISEASE_MAX=$(cat /tmp/du_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/du_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/du_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/du_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/du_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Domiciliary Unit Created ---
DU_RECORD=$(gnuhealth_db_query "
    SELECT id, name
    FROM gnuhealth_du
    WHERE name = 'DU-CAPUT-001'
      AND id > $BASELINE_DU_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

DU_CREATED="false"
DU_ID="null"
if [ -n "$DU_RECORD" ]; then
    DU_CREATED="true"
    DU_ID=$(echo "$DU_RECORD" | awk -F'|' '{print $1}' | tr -d ' ')
fi

ANY_NEW_DU=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_du WHERE id > $BASELINE_DU_MAX
" 2>/dev/null | tr -d '[:space:]')

echo "DU Created: $DU_CREATED (ID: $DU_ID), Any new DU: ${ANY_NEW_DU:-0}"

# --- Check 2: Patient Linked to DU ---
PATIENT_DU=$(gnuhealth_db_query "
    SELECT COALESCE(du::text, 'null')
    FROM gnuhealth_patient
    WHERE id = $TARGET_PATIENT_ID
" 2>/dev/null | tr -d '[:space:]')

PATIENT_LINKED="false"
if [ "$DU_CREATED" = "true" ] && [ "$PATIENT_DU" = "$DU_ID" ]; then
    PATIENT_LINKED="true"
fi
echo "Patient DU ID: $PATIENT_DU (Expected: $DU_ID) -> Linked: $PATIENT_LINKED"

# --- Check 3: COPD Diagnosis (J44.x) ---
J44_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'J44%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

J44_FOUND="false"
J44_ACTIVE="false"
J44_CODE="null"
if [ -n "$J44_RECORD" ]; then
    J44_FOUND="true"
    J44_CODE=$(echo "$J44_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$J44_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        J44_ACTIVE="true"
    fi
fi

ANY_J_CODE=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'J%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

ANY_J_CODE_FOUND="false"
if [ -n "$ANY_J_CODE" ]; then
    ANY_J_CODE_FOUND="true"
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

echo "J44 Found: $J44_FOUND ($J44_CODE, Active: $J44_ACTIVE), Any J-code: $ANY_J_CODE_FOUND, Any new disease: ${ANY_NEW_DISEASE:-0}"

# --- Check 4: Laboratory Orders (>= 2) ---
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

echo "New Lab Orders: ${NEW_LAB_COUNT:-0} (Types: $NEW_LAB_TYPES)"

# --- Check 5: Follow-up Appointment (30-60 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date::date, (appointment_date::date - CURRENT_DATE) as days_out
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS_OUT="-999"

if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DAYS_OUT=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi
echo "Appointment Found: $APPT_FOUND (Days out: $APPT_DAYS_OUT)"

# Check if ANY new appointment exists regardless of patient (for partial credit detection)
ANY_NEW_APPT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_appointment
    WHERE id > $BASELINE_APPT_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Generate JSON Result ---
TEMP_JSON=$(mktemp /tmp/record_domiciliary_unit_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "Bonifacio Caput",
    "du_created": $DU_CREATED,
    "du_id": "$DU_ID",
    "any_new_du_count": ${ANY_NEW_DU:-0},
    "patient_du_field": "$PATIENT_DU",
    "patient_linked_correctly": $PATIENT_LINKED,
    "j44_found": $J44_FOUND,
    "j44_active": $J44_ACTIVE,
    "j44_code": "$J44_CODE",
    "any_j_code_found": $ANY_J_CODE_FOUND,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "appointment_found": $APPT_FOUND,
    "appointment_days_out": "$APPT_DAYS_OUT",
    "any_new_appointment_count": ${ANY_NEW_APPT:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Make readable and safe
rm -f /tmp/record_domiciliary_unit_result.json 2>/dev/null || sudo rm -f /tmp/record_domiciliary_unit_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/record_domiciliary_unit_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/record_domiciliary_unit_result.json
chmod 666 /tmp/record_domiciliary_unit_result.json 2>/dev/null || sudo chmod 666 /tmp/record_domiciliary_unit_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/record_domiciliary_unit_result.json"
cat /tmp/record_domiciliary_unit_result.json
echo "=== Export Complete ==="