#!/bin/bash
echo "=== Exporting hypertension_care_protocol result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/htn_final_state.png

# --- Load baseline values ---
BASELINE_DISEASE_MAX=$(cat /tmp/htn_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/htn_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/htn_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/htn_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/htn_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/htn_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"
echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline prescription max: $BASELINE_PRESCRIPTION_MAX"
echo "Baseline lab max: $BASELINE_LAB_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

# --- Check 1: I10 disease record for Roberto Carlos (new, active) ---
I10_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code = 'I10'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC
    LIMIT 1" 2>/dev/null | head -1)

I10_FOUND="false"
I10_ACTIVE="false"
if [ -n "$I10_RECORD" ]; then
    I10_FOUND="true"
    # Check is_active column
    ACTIVE_VAL=$(echo "$I10_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        I10_ACTIVE="true"
    fi
fi
echo "I10 disease found: $I10_FOUND, active: $I10_ACTIVE"

# --- Check 2: Any new prescription for Roberto Carlos (new since baseline) ---
PRESC_ROW=$(gnuhealth_db_query "
    SELECT po.id, COALESCE(po.date_prescribed::text, po.create_date::text, 'unknown')
    FROM gnuhealth_prescription_order po
    WHERE po.patient = $TARGET_PATIENT_ID
      AND po.id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY po.id DESC
    LIMIT 1" 2>/dev/null | head -1)

PRESCRIPTION_FOUND="false"
PRESCRIPTION_ID="null"
if [ -n "$PRESC_ROW" ]; then
    PRESCRIPTION_FOUND="true"
    PRESCRIPTION_ID=$(echo "$PRESC_ROW" | awk -F'|' '{print $1}' | tr -d ' ')
fi
echo "Prescription found: $PRESCRIPTION_FOUND (id=$PRESCRIPTION_ID)"

# --- Check 2b: Try to verify Amlodipine specifically ---
AMLODIPINE_FOUND="false"
if [ "$PRESCRIPTION_FOUND" = "true" ]; then
    # Try to find the drug name in prescription lines
    # gnuhealth_prescription_order_line references medicament which is a product
    AML_CHECK=$(gnuhealth_db_query "
        SELECT COUNT(*) FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND LOWER(pt.name) LIKE '%amlodip%'
    " 2>/dev/null | tr -d '[:space:]')
    if [ "${AML_CHECK:-0}" -gt 0 ]; then
        AMLODIPINE_FOUND="true"
    fi
fi
echo "Amlodipine specifically found: $AMLODIPINE_FOUND"

# --- Check 3: Lab test order for Roberto Carlos (new since baseline) ---
LAB_ROW=$(gnuhealth_db_query "
    SELECT glt.id, COALESCE(ltt.code, ltt.name)
    FROM gnuhealth_patient_lab_test glt
    JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
    WHERE glt.patient_id = $TARGET_PATIENT_ID
      AND glt.id > $BASELINE_LAB_MAX
    ORDER BY glt.id DESC
    LIMIT 1" 2>/dev/null | head -1)

LAB_FOUND="false"
LAB_TYPE="unknown"
if [ -n "$LAB_ROW" ]; then
    LAB_FOUND="true"
    LAB_TYPE=$(echo "$LAB_ROW" | awk -F'|' '{print $2}' | tr -d ' ')
fi
echo "Lab order found: $LAB_FOUND (type=$LAB_TYPE)"

# Check if it's a lipid-related test
LIPID_FOUND="false"
if [ "$LAB_FOUND" = "true" ]; then
    LIPID_CHECK=$(gnuhealth_db_query "
        SELECT COUNT(*) FROM gnuhealth_patient_lab_test glt
        JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
        WHERE glt.patient_id = $TARGET_PATIENT_ID
          AND glt.id > $BASELINE_LAB_MAX
          AND (UPPER(ltt.code) LIKE '%LIPID%' OR UPPER(ltt.name) LIKE '%LIPID%'
               OR UPPER(ltt.name) LIKE '%CHOLESTEROL%' OR UPPER(ltt.name) LIKE '%TRIGLYCERIDE%')
    " 2>/dev/null | tr -d '[:space:]')
    if [ "${LIPID_CHECK:-0}" -gt 0 ]; then
        LIPID_FOUND="true"
    fi
fi
echo "Lipid-specific lab found: $LIPID_FOUND"

# --- Check 4: Follow-up appointment for Roberto Carlos with Dr. Cordara (18-42 days) ---
FOLLOWUP_DATE_MIN=$(date -d "$TASK_START_DATE + 17 days" +%Y-%m-%d 2>/dev/null || date -v+17d -j -f "%Y-%m-%d" "$TASK_START_DATE" +%Y-%m-%d 2>/dev/null || echo "2026-01-01")
FOLLOWUP_DATE_MAX=$(date -d "$TASK_START_DATE + 43 days" +%Y-%m-%d 2>/dev/null || date -v+43d -j -f "%Y-%m-%d" "$TASK_START_DATE" +%Y-%m-%d 2>/dev/null || echo "2027-12-31")

APPT_ROW=$(gnuhealth_db_query "
    SELECT ga.id, ga.appointment_date::date::text
    FROM gnuhealth_appointment ga
    JOIN gnuhealth_healthprofessional hp ON ga.healthprof = hp.id
    JOIN party_party hpparty ON hp.party = hpparty.id
    WHERE ga.patient = $TARGET_PATIENT_ID
      AND ga.id > $BASELINE_APPT_MAX
      AND ga.appointment_date::date >= '$FOLLOWUP_DATE_MIN'
      AND ga.appointment_date::date <= '$FOLLOWUP_DATE_MAX'
    LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="null"
if [ -n "$APPT_ROW" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_ROW" | awk -F'|' '{print $2}' | tr -d ' ')
fi
echo "Follow-up appointment found: $APPT_FOUND (date=$APPT_DATE)"

# Also check any new appointment regardless of date (for partial credit)
ANY_APPT_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Any new appointment count: ${ANY_APPT_COUNT:-0}"

# --- Write result JSON ---
RESULT_JSON="{
  \"task\": \"hypertension_care_protocol\",
  \"target_patient_id\": $TARGET_PATIENT_ID,
  \"target_patient_name\": \"Roberto Carlos\",
  \"baseline_disease_max\": $BASELINE_DISEASE_MAX,
  \"baseline_prescription_max\": $BASELINE_PRESCRIPTION_MAX,
  \"baseline_lab_max\": $BASELINE_LAB_MAX,
  \"baseline_appt_max\": $BASELINE_APPT_MAX,
  \"task_start_date\": \"$TASK_START_DATE\",
  \"i10_disease_found\": $I10_FOUND,
  \"i10_disease_active\": $I10_ACTIVE,
  \"prescription_found\": $PRESCRIPTION_FOUND,
  \"prescription_id\": $PRESCRIPTION_ID,
  \"amlodipine_found\": $AMLODIPINE_FOUND,
  \"lab_order_found\": $LAB_FOUND,
  \"lab_order_type\": \"$(json_escape "$LAB_TYPE")\",
  \"lipid_lab_found\": $LIPID_FOUND,
  \"followup_appt_in_range\": $APPT_FOUND,
  \"followup_appt_date\": \"$APPT_DATE\",
  \"followup_window_min\": \"$FOLLOWUP_DATE_MIN\",
  \"followup_window_max\": \"$FOLLOWUP_DATE_MAX\",
  \"any_new_appt_count\": ${ANY_APPT_COUNT:-0}
}"

safe_write_result "/tmp/hypertension_care_protocol_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/hypertension_care_protocol_result.json"
echo "=== Export Complete ==="
