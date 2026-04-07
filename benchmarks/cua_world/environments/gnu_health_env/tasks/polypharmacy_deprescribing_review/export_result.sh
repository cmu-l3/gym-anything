#!/bin/bash
echo "=== Exporting polypharmacy_deprescribing_review result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/poly_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/poly_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_ALLERGY_MAX=$(cat /tmp/poly_baseline_allergy_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/poly_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/poly_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/poly_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/poly_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/poly_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Fall-related diagnosis (W-code or S-code) ---
FALL_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'W%' OR gpath.code LIKE 'S%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

FALL_FOUND="false"
FALL_CODE="null"
FALL_ACTIVE="false"
if [ -n "$FALL_RECORD" ]; then
    FALL_FOUND="true"
    FALL_CODE=$(echo "$FALL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$FALL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        FALL_ACTIVE="true"
    fi
fi

# Also check any new disease (for partial credit if wrong code category)
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Fall diagnosis: found=$FALL_FOUND code=$FALL_CODE active=$FALL_ACTIVE, any new disease: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: ACE inhibitor adverse reaction/allergy ---
ALLERGY_RECORD=$(gnuhealth_db_query "
    SELECT id, allergen, COALESCE(severity, 'unknown')
    FROM gnuhealth_patient_allergy
    WHERE patient = $TARGET_PATIENT_ID
      AND (LOWER(allergen) LIKE '%enalapril%'
           OR LOWER(allergen) LIKE '%ace%inhibitor%'
           OR LOWER(allergen) LIKE '%lisinopril%'
           OR LOWER(allergen) LIKE '%captopril%'
           OR LOWER(allergen) LIKE '%ramipril%'
           OR LOWER(allergen) LIKE '%benazepril%')
      AND id > $BASELINE_ALLERGY_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

ACE_ALLERGY_FOUND="false"
ACE_ALLERGEN="null"
ACE_SEVERITY="unknown"
if [ -n "$ALLERGY_RECORD" ]; then
    ACE_ALLERGY_FOUND="true"
    ACE_ALLERGEN=$(echo "$ALLERGY_RECORD" | awk -F'|' '{print $2}')
    ACE_SEVERITY=$(echo "$ALLERGY_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi

# Fallback: any new allergy at all
ANY_NEW_ALLERGY=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_allergy
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_ALLERGY_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "ACE allergy: found=$ACE_ALLERGY_FOUND allergen=$ACE_ALLERGEN severity=$ACE_SEVERITY, any new: ${ANY_NEW_ALLERGY:-0}"

# --- Check 3: Safer antihypertensive prescription (non-ACE) ---
PRESC_FOUND="false"
SAFE_ANTIHTN_FOUND="false"
SAFE_DRUG_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    # Check for ARB, CCB, or thiazide (safer alternatives)
    SAFE_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%losartan%'
               OR LOWER(pt.name) LIKE '%valsartan%'
               OR LOWER(pt.name) LIKE '%irbesartan%'
               OR LOWER(pt.name) LIKE '%candesartan%'
               OR LOWER(pt.name) LIKE '%telmisartan%'
               OR LOWER(pt.name) LIKE '%amlodip%'
               OR LOWER(pt.name) LIKE '%nifedip%'
               OR LOWER(pt.name) LIKE '%diltiazem%'
               OR LOWER(pt.name) LIKE '%hydrochlorothiazid%'
               OR LOWER(pt.name) LIKE '%chlorthalidon%'
               OR LOWER(pt.name) LIKE '%indapamid%'
               OR LOWER(pt.name) LIKE '%atenolol%'
               OR LOWER(pt.name) LIKE '%metoprolol%'
               OR LOWER(pt.name) LIKE '%bisoprolol%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$SAFE_CHECK" ]; then
        SAFE_ANTIHTN_FOUND="true"
        SAFE_DRUG_NAME="$SAFE_CHECK"
    fi

    # Check it's NOT an ACE inhibitor (would be wrong)
    ACE_PRESCRIBED=$(gnuhealth_db_query "
        SELECT COUNT(*)
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%enalapril%'
               OR LOWER(pt.name) LIKE '%lisinopril%'
               OR LOWER(pt.name) LIKE '%captopril%'
               OR LOWER(pt.name) LIKE '%ramipril%')
    " 2>/dev/null | tr -d '[:space:]')
fi
echo "Prescription found: $PRESC_FOUND, safe antihypertensive: $SAFE_ANTIHTN_FOUND ($SAFE_DRUG_NAME), ACE re-prescribed: ${ACE_PRESCRIBED:-0}"

# --- Check 4: Post-fall lab orders (>= 2) ---
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
echo "New lab orders: ${NEW_LAB_COUNT:-0} (types: $NEW_LAB_TYPES)"

# --- Check 5: Medication review follow-up (7-21 days) ---
FOLLOWUP_MIN=$(date -d "$TASK_START_DATE + 6 days" +%Y-%m-%d 2>/dev/null || echo "2026-01-01")
FOLLOWUP_MAX=$(date -d "$TASK_START_DATE + 22 days" +%Y-%m-%d 2>/dev/null || echo "2027-12-31")

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

ANY_NEW_APPTS=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Follow-up (7-21d): $APPT_FOUND (date=$APPT_DATE), any new: ${ANY_NEW_APPTS:-0}"

# --- Build result JSON ---
RESULT_JSON="{
  \"task\": \"polypharmacy_deprescribing_review\",
  \"target_patient_id\": $TARGET_PATIENT_ID,
  \"target_patient_name\": \"Roberto Carlos\",
  \"task_start_date\": \"$TASK_START_DATE\",
  \"fall_diagnosis_found\": $FALL_FOUND,
  \"fall_diagnosis_code\": \"$(json_escape "$FALL_CODE")\",
  \"fall_diagnosis_active\": $FALL_ACTIVE,
  \"any_new_disease_count\": ${ANY_NEW_DISEASE:-0},
  \"ace_allergy_found\": $ACE_ALLERGY_FOUND,
  \"ace_allergen\": \"$(json_escape "$ACE_ALLERGEN")\",
  \"ace_severity\": \"$(json_escape "$ACE_SEVERITY")\",
  \"any_new_allergy_count\": ${ANY_NEW_ALLERGY:-0},
  \"prescription_found\": $PRESC_FOUND,
  \"safe_antihypertensive_found\": $SAFE_ANTIHTN_FOUND,
  \"safe_drug_name\": \"$(json_escape "$SAFE_DRUG_NAME")\",
  \"ace_re_prescribed\": ${ACE_PRESCRIBED:-0},
  \"new_lab_count\": ${NEW_LAB_COUNT:-0},
  \"new_lab_types\": \"$(json_escape "$NEW_LAB_TYPES")\",
  \"followup_appt_in_range\": $APPT_FOUND,
  \"followup_appt_date\": \"$APPT_DATE\",
  \"followup_window_min\": \"$FOLLOWUP_MIN\",
  \"followup_window_max\": \"$FOLLOWUP_MAX\",
  \"any_new_appt_count\": ${ANY_NEW_APPTS:-0}
}"

safe_write_result "/tmp/polypharmacy_deprescribing_review_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/polypharmacy_deprescribing_review_result.json"
echo "=== Export Complete ==="
