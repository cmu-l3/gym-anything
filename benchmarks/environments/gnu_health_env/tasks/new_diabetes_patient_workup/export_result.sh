#!/bin/bash
echo "=== Exporting new_diabetes_patient_workup result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/dm_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/dm_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_ALLERGY_MAX=$(cat /tmp/dm_baseline_allergy_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/dm_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/dm_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/dm_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/dm_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/dm_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: E11 disease record (new, active) ---
E11_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code = 'E11'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC
    LIMIT 1" 2>/dev/null | head -1)

E11_FOUND="false"
E11_ACTIVE="false"
if [ -n "$E11_RECORD" ]; then
    E11_FOUND="true"
    ACTIVE_VAL=$(echo "$E11_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        E11_ACTIVE="true"
    fi
fi
echo "E11 disease found: $E11_FOUND, active: $E11_ACTIVE"

# --- Check 2: Penicillin allergy (new) ---
ALLERGY_RECORD=$(gnuhealth_db_query "
    SELECT id, allergen, severity
    FROM gnuhealth_patient_allergy
    WHERE patient = $TARGET_PATIENT_ID
      AND LOWER(allergen) LIKE '%penicillin%'
      AND id > $BASELINE_ALLERGY_MAX
    ORDER BY id DESC
    LIMIT 1" 2>/dev/null | head -1)

ALLERGY_FOUND="false"
ALLERGY_SEVERITY="unknown"
if [ -n "$ALLERGY_RECORD" ]; then
    ALLERGY_FOUND="true"
    ALLERGY_SEVERITY=$(echo "$ALLERGY_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi
echo "Penicillin allergy found: $ALLERGY_FOUND (severity=$ALLERGY_SEVERITY)"

# Fallback: check by just patient_id (no baseline filter) in case table doesn't have allergy_max
ALLERGY_COUNT_TOTAL=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_allergy
    WHERE patient = $TARGET_PATIENT_ID
      AND LOWER(allergen) LIKE '%penicillin%'
" 2>/dev/null | tr -d '[:space:]')
echo "Total penicillin allergy records: ${ALLERGY_COUNT_TOTAL:-0}"

# --- Check 3: HbA1c lab test order (new) ---
LAB_RECORD=$(gnuhealth_db_query "
    SELECT glt.id, ltt.code, ltt.name
    FROM gnuhealth_patient_lab_test glt
    JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
    WHERE glt.patient_id = $TARGET_PATIENT_ID
      AND (ltt.code = 'HBA1C' OR UPPER(ltt.name) LIKE '%HBA1C%' OR UPPER(ltt.name) LIKE '%GLYCATED%')
      AND glt.id > $BASELINE_LAB_MAX
    ORDER BY glt.id DESC
    LIMIT 1" 2>/dev/null | head -1)

HBAC_FOUND="false"
if [ -n "$LAB_RECORD" ]; then
    HBAC_FOUND="true"
fi
echo "HbA1c lab order found: $HBAC_FOUND"

# --- Check 4: Metformin prescription (new) ---
PRESC_FOUND="false"
METFORMIN_FOUND="false"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"
    # Try to check for Metformin in prescription lines
    MET_CHECK=$(gnuhealth_db_query "
        SELECT COUNT(*)
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND LOWER(pt.name) LIKE '%metformin%'
    " 2>/dev/null | tr -d '[:space:]')
    if [ "${MET_CHECK:-0}" -gt 0 ]; then
        METFORMIN_FOUND="true"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Metformin confirmed: $METFORMIN_FOUND"

# --- Check 5: Follow-up appointment (35-60 days) ---
FOLLOWUP_MIN=$(date -d "$TASK_START_DATE + 34 days" +%Y-%m-%d 2>/dev/null || echo "2026-01-01")
FOLLOWUP_MAX=$(date -d "$TASK_START_DATE + 61 days" +%Y-%m-%d 2>/dev/null || echo "2027-12-31")

APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date::text
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
      AND appointment_date::date >= '$FOLLOWUP_MIN'
      AND appointment_date::date <= '$FOLLOWUP_MAX'
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="null"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi
echo "Follow-up appointment (35-60d): $APPT_FOUND (date=$APPT_DATE)"

ANY_APPT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Any new appointment count: ${ANY_APPT:-0}"

# --- Build result JSON ---
RESULT_JSON="{
  \"task\": \"new_diabetes_patient_workup\",
  \"target_patient_id\": $TARGET_PATIENT_ID,
  \"target_patient_name\": \"Bonifacio Caput\",
  \"task_start_date\": \"$TASK_START_DATE\",
  \"e11_disease_found\": $E11_FOUND,
  \"e11_disease_active\": $E11_ACTIVE,
  \"penicillin_allergy_found\": $ALLERGY_FOUND,
  \"penicillin_allergy_severity\": \"$(json_escape "$ALLERGY_SEVERITY")\",
  \"penicillin_allergy_total\": ${ALLERGY_COUNT_TOTAL:-0},
  \"hba1c_lab_found\": $HBAC_FOUND,
  \"prescription_found\": $PRESC_FOUND,
  \"metformin_confirmed\": $METFORMIN_FOUND,
  \"followup_appt_in_range\": $APPT_FOUND,
  \"followup_appt_date\": \"$APPT_DATE\",
  \"followup_window_min\": \"$FOLLOWUP_MIN\",
  \"followup_window_max\": \"$FOLLOWUP_MAX\",
  \"any_new_appt_count\": ${ANY_APPT:-0}
}"

safe_write_result "/tmp/new_diabetes_patient_workup_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/new_diabetes_patient_workup_result.json"
echo "=== Export Complete ==="
