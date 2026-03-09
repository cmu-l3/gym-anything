#!/bin/bash
echo "=== Exporting abnormal_hba1c_management result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/hbac_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/hbac_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/hbac_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/hbac_baseline_appt_max 2>/dev/null || echo "0")
BASELINE_LAB_BEFORE_SEED=$(cat /tmp/hbac_baseline_lab_before_seed 2>/dev/null || echo "0")
SEEDED_LAB_ID=$(cat /tmp/hbac_seeded_lab_id 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/hbac_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/hbac_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"
echo "Seeded lab id: $SEEDED_LAB_ID"

# --- Check 1: HbA1c lab test state and result ---
# Check if the seeded lab test is now in a completed/validated state
LAB_STATE="unknown"
LAB_RESULT_VALUE="null"
LAB_COMPLETED="false"
LAB_RESULT_ENTERED="false"

if [ -n "$SEEDED_LAB_ID" ] && [ "$SEEDED_LAB_ID" != "0" ]; then
    # Check the state of the seeded lab test
    LAB_STATE=$(gnuhealth_db_query "
        SELECT state FROM gnuhealth_patient_lab_test
        WHERE id = $SEEDED_LAB_ID
    " 2>/dev/null | tr -d '[:space:]')
    echo "Seeded lab test state: ${LAB_STATE:-unknown}"

    if [ "$LAB_STATE" = "validated" ] || [ "$LAB_STATE" = "done" ] || [ "$LAB_STATE" = "complete" ] || [ "$LAB_STATE" = "signed" ]; then
        LAB_COMPLETED="true"
    fi

    # Check for HbA1c result value in lab test criteria results
    # gnuhealth_lab_test_critearea stores the criteria; gnuhealth_patient_lab_test_critearea stores results
    # The result table name varies; try common patterns
    RESULT_TABLE_CHECK=$(gnuhealth_db_query "
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public'
          AND (table_name LIKE '%lab_test%result%' OR table_name LIKE '%patient_lab%crit%')
        LIMIT 5
    " 2>/dev/null)
    echo "Lab result tables found: $RESULT_TABLE_CHECK"

    # Try the standard GNU Health result table pattern
    LAB_RESULT_VALUE=$(gnuhealth_db_query "
        SELECT result FROM gnuhealth_patient_lab_test_critearea
        WHERE test_id = $SEEDED_LAB_ID
        LIMIT 1
    " 2>/dev/null | tr -d '[:space:]')

    if [ -z "$LAB_RESULT_VALUE" ]; then
        # Alternative table name
        LAB_RESULT_VALUE=$(gnuhealth_db_query "
            SELECT result FROM gnuhealth_lab_test_result
            WHERE test = $SEEDED_LAB_ID
            LIMIT 1
        " 2>/dev/null | tr -d '[:space:]')
    fi

    if [ -n "$LAB_RESULT_VALUE" ] && [ "$LAB_RESULT_VALUE" != "null" ]; then
        LAB_RESULT_ENTERED="true"
        # Parse the float value for range check
        IS_VALID_RANGE=$(echo "$LAB_RESULT_VALUE" | awk '{
            v = $1 + 0;
            if (v >= 9.0 && v <= 9.8) print "true";
            else print "false";
        }' 2>/dev/null || echo "unknown")
        echo "HbA1c result value: $LAB_RESULT_VALUE (valid range 9.0-9.8: $IS_VALID_RANGE)"
    fi
fi

# Also check if any HbA1c lab for Ana is in completed state (even if seeded ID failed)
ANY_COMPLETED_HBAC=$(gnuhealth_db_query "
    SELECT COUNT(*)
    FROM gnuhealth_patient_lab_test glt
    JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
    WHERE glt.patient_id = $TARGET_PATIENT_ID
      AND (ltt.code = 'HBA1C' OR UPPER(ltt.name) LIKE '%GLYCATED%')
      AND glt.state IN ('validated', 'done', 'complete', 'signed')
" 2>/dev/null | tr -d '[:space:]')
echo "Any completed HbA1c labs for Ana: ${ANY_COMPLETED_HBAC:-0}"

IS_VALID_RANGE="${IS_VALID_RANGE:-false}"
LAB_RESULT_VALUE="${LAB_RESULT_VALUE:-null}"

# --- Check 2: New E10.x condition record ---
E10_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'E10%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC
    LIMIT 1
" 2>/dev/null | head -1)

E10_FOUND="false"
E10_CODE="null"
if [ -n "$E10_RECORD" ]; then
    E10_FOUND="true"
    E10_CODE=$(echo "$E10_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi
echo "New E10.x condition: $E10_FOUND (code=$E10_CODE)"

# --- Check 3: New insulin prescription ---
PRESC_FOUND="false"
INSULIN_CONFIRMED="false"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"
    # Check for insulin in prescription lines
    INSULIN_CHECK=$(gnuhealth_db_query "
        SELECT COUNT(*)
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%insulin%' OR LOWER(pt.name) LIKE '%lispro%'
               OR LOWER(pt.name) LIKE '%glargine%' OR LOWER(pt.name) LIKE '%novolog%'
               OR LOWER(pt.name) LIKE '%humalog%' OR LOWER(pt.name) LIKE '%lantus%')
    " 2>/dev/null | tr -d '[:space:]')
    if [ "${INSULIN_CHECK:-0}" -gt 0 ]; then
        INSULIN_CONFIRMED="true"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Insulin confirmed: $INSULIN_CONFIRMED"

# --- Check 4: Urgent follow-up appointment (7-28 days) ---
URGENT_MIN=$(date -d "$TASK_START_DATE + 6 days" +%Y-%m-%d 2>/dev/null || echo "2026-01-01")
URGENT_MAX=$(date -d "$TASK_START_DATE + 29 days" +%Y-%m-%d 2>/dev/null || echo "2027-12-31")

APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date::text
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
      AND appointment_date::date >= '$URGENT_MIN'
      AND appointment_date::date <= '$URGENT_MAX'
    ORDER BY appointment_date LIMIT 1
" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="null"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi
echo "Urgent follow-up (7-28d): $APPT_FOUND (date=$APPT_DATE)"

ANY_NEW_APPT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Build result JSON ---
RESULT_JSON="{
  \"task\": \"abnormal_hba1c_management\",
  \"target_patient_id\": $TARGET_PATIENT_ID,
  \"target_patient_name\": \"Ana Isabel Betz\",
  \"task_start_date\": \"$TASK_START_DATE\",
  \"seeded_lab_id\": ${SEEDED_LAB_ID:-0},
  \"lab_state\": \"$(json_escape "$LAB_STATE")\",
  \"lab_completed\": $LAB_COMPLETED,
  \"lab_result_entered\": $LAB_RESULT_ENTERED,
  \"lab_result_value\": \"$(json_escape "$LAB_RESULT_VALUE")\",
  \"lab_result_in_valid_range\": $IS_VALID_RANGE,
  \"any_completed_hbac_count\": ${ANY_COMPLETED_HBAC:-0},
  \"e10_condition_found\": $E10_FOUND,
  \"e10_code\": \"$(json_escape "$E10_CODE")\",
  \"prescription_found\": $PRESC_FOUND,
  \"insulin_confirmed\": $INSULIN_CONFIRMED,
  \"urgent_appt_in_range\": $APPT_FOUND,
  \"urgent_appt_date\": \"$APPT_DATE\",
  \"urgent_window_min\": \"$URGENT_MIN\",
  \"urgent_window_max\": \"$URGENT_MAX\",
  \"any_new_appt_count\": ${ANY_NEW_APPT:-0}
}"

safe_write_result "/tmp/abnormal_hba1c_management_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/abnormal_hba1c_management_result.json"
echo "=== Export Complete ==="
