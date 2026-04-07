#!/bin/bash
echo "=== Exporting workplace_chemical_exposure_protocol result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/occ_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/occ_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/occ_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/occ_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/occ_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/occ_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/occ_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/occ_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Chemical burn T-code diagnosis ---
T_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'T%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

T_FOUND="false"
T_CODE="null"
T_ACTIVE="false"
if [ -n "$T_RECORD" ]; then
    T_FOUND="true"
    T_CODE=$(echo "$T_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$T_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        T_ACTIVE="true"
    fi
fi

# Check specifically for T54 (corrosive substances) or L-code chemical dermatitis
T54_FOUND="false"
T54_CHECK=$(gnuhealth_db_query "
    SELECT gpath.code
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'T54%' OR gpath.code LIKE 'T20%' OR gpath.code LIKE 'T21%'
           OR gpath.code LIKE 'T22%' OR gpath.code LIKE 'T23%' OR gpath.code LIKE 'T30%'
           OR gpath.code LIKE 'L24%' OR gpath.code LIKE 'L25%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$T54_CHECK" ]; then
    T54_FOUND="true"
fi

# Any new disease at all
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "T-code: found=$T_FOUND code=$T_CODE active=$T_ACTIVE, T54/burn-specific=$T54_FOUND, any new: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Clinical evaluation ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(temperature::text,'null'), COALESCE(heart_rate::text,'null'),
           COALESCE(chief_complaint,'')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_TEMP="null"
EVAL_HR="null"
EVAL_CHIEF="null"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_TEMP=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    EVAL_CHIEF=$(echo "$EVAL_RECORD" | awk -F'|' '{print $4}')
fi
echo "Evaluation: found=$EVAL_FOUND, temp=$EVAL_TEMP, HR=$EVAL_HR"

# --- Check 3: Wound care prescription ---
PRESC_FOUND="false"
WOUND_CARE_FOUND="false"
WOUND_DRUG_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    WOUND_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%silver%sulfadiaz%'
               OR LOWER(pt.name) LIKE '%bacitracin%'
               OR LOWER(pt.name) LIKE '%mupirocin%'
               OR LOWER(pt.name) LIKE '%neomycin%'
               OR LOWER(pt.name) LIKE '%fusidic%'
               OR LOWER(pt.name) LIKE '%sulfadiazine%'
               OR LOWER(pt.name) LIKE '%mafenide%'
               OR LOWER(pt.name) LIKE '%chlorhexidine%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$WOUND_CHECK" ]; then
        WOUND_CARE_FOUND="true"
        WOUND_DRUG_NAME="$WOUND_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Wound care: $WOUND_CARE_FOUND ($WOUND_DRUG_NAME)"

# --- Check 4: Toxicology/baseline labs (>= 2) ---
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

# --- Check 5: Wound reassessment follow-up (3-10 days) ---
FOLLOWUP_MIN=$(date -d "$TASK_START_DATE + 2 days" +%Y-%m-%d 2>/dev/null || echo "2026-01-01")
FOLLOWUP_MAX=$(date -d "$TASK_START_DATE + 11 days" +%Y-%m-%d 2>/dev/null || echo "2027-12-31")

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
echo "Wound follow-up (3-10d): $APPT_FOUND (date=$APPT_DATE), any new: ${ANY_NEW_APPTS:-0}"

# --- Build result JSON ---
RESULT_JSON="{
  \"task\": \"workplace_chemical_exposure_protocol\",
  \"target_patient_id\": $TARGET_PATIENT_ID,
  \"target_patient_name\": \"Bonifacio Caput\",
  \"task_start_date\": \"$TASK_START_DATE\",
  \"t_code_found\": $T_FOUND,
  \"t_code\": \"$(json_escape "$T_CODE")\",
  \"t_code_active\": $T_ACTIVE,
  \"t54_burn_specific\": $T54_FOUND,
  \"any_new_disease_count\": ${ANY_NEW_DISEASE:-0},
  \"evaluation_found\": $EVAL_FOUND,
  \"evaluation_temperature\": \"$(json_escape "$EVAL_TEMP")\",
  \"evaluation_heart_rate\": \"$(json_escape "$EVAL_HR")\",
  \"evaluation_chief_complaint\": \"$(json_escape "$EVAL_CHIEF")\",
  \"prescription_found\": $PRESC_FOUND,
  \"wound_care_found\": $WOUND_CARE_FOUND,
  \"wound_drug_name\": \"$(json_escape "$WOUND_DRUG_NAME")\",
  \"new_lab_count\": ${NEW_LAB_COUNT:-0},
  \"new_lab_types\": \"$(json_escape "$NEW_LAB_TYPES")\",
  \"followup_appt_in_range\": $APPT_FOUND,
  \"followup_appt_date\": \"$APPT_DATE\",
  \"followup_window_min\": \"$FOLLOWUP_MIN\",
  \"followup_window_max\": \"$FOLLOWUP_MAX\",
  \"any_new_appt_count\": ${ANY_NEW_APPTS:-0}
}"

safe_write_result "/tmp/workplace_chemical_exposure_protocol_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/workplace_chemical_exposure_protocol_result.json"
echo "=== Export Complete ==="
