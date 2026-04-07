#!/bin/bash
echo "=== Exporting perioperative_appendectomy_management result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/appx_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/appx_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/appx_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/appx_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/appx_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/appx_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/appx_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/appx_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: K35.x appendicitis diagnosis (new, active) ---
K35_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'K35%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC
    LIMIT 1" 2>/dev/null | head -1)

K35_FOUND="false"
K35_ACTIVE="false"
K35_CODE="null"
if [ -n "$K35_RECORD" ]; then
    K35_FOUND="true"
    K35_CODE=$(echo "$K35_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$K35_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        K35_ACTIVE="true"
    fi
fi

# Also check for any K-code appendicitis diagnosis (K36, K37 as alternatives)
ANY_APPENDICITIS=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'K35%' OR gpath.code LIKE 'K36%' OR gpath.code LIKE 'K37%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

ANY_APPENDICITIS_FOUND="false"
ANY_APPENDICITIS_CODE="null"
if [ -n "$ANY_APPENDICITIS" ]; then
    ANY_APPENDICITIS_FOUND="true"
    ANY_APPENDICITIS_CODE=$(echo "$ANY_APPENDICITIS" | awk -F'|' '{print $2}' | tr -d ' ')
fi
echo "K35 found: $K35_FOUND (code=$K35_CODE, active=$K35_ACTIVE), any appendicitis: $ANY_APPENDICITIS_FOUND ($ANY_APPENDICITIS_CODE)"

# --- Check 2: Clinical evaluation with fever and tachycardia ---
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
EVAL_HAS_FEVER="false"
EVAL_HAS_TACHYCARDIA="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_TEMP=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')

    if echo "$EVAL_TEMP" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        FEVER_CHECK=$(echo "$EVAL_TEMP" | awk '{if ($1 >= 38.0) print "true"; else print "false"}')
        EVAL_HAS_FEVER="${FEVER_CHECK:-false}"
    fi

    if echo "$EVAL_HR" | grep -qE '^[0-9]+$'; then
        TACHY_CHECK=$(echo "$EVAL_HR" | awk '{if ($1 >= 100) print "true"; else print "false"}')
        EVAL_HAS_TACHYCARDIA="${TACHY_CHECK:-false}"
    fi
fi
echo "Evaluation: found=$EVAL_FOUND, temp=$EVAL_TEMP (fever=$EVAL_HAS_FEVER), HR=$EVAL_HR (tachy=$EVAL_HAS_TACHYCARDIA)"

# --- Check 3: Pre-operative lab orders (need >= 3) ---
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

# --- Check 4: Perioperative antibiotic prescription ---
PRESC_FOUND="false"
ANTIBIOTIC_FOUND="false"
ANTIBIOTIC_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    ABX_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%ceftriaxon%'
               OR LOWER(pt.name) LIKE '%metronidazol%'
               OR LOWER(pt.name) LIKE '%piperacillin%'
               OR LOWER(pt.name) LIKE '%tazobactam%'
               OR LOWER(pt.name) LIKE '%cefazolin%'
               OR LOWER(pt.name) LIKE '%amoxicillin%clavulan%')
        LIMIT 1
    " 2>/dev/null | head -1 | tr -d '[:space:]')

    if [ -n "$ABX_CHECK" ]; then
        ANTIBIOTIC_FOUND="true"
        ANTIBIOTIC_NAME="$ABX_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Antibiotic: $ANTIBIOTIC_FOUND ($ANTIBIOTIC_NAME)"

# --- Check 5: Post-discharge follow-up (7-14 days) ---
FOLLOWUP_MIN=$(date -d "$TASK_START_DATE + 6 days" +%Y-%m-%d 2>/dev/null || echo "2026-01-01")
FOLLOWUP_MAX=$(date -d "$TASK_START_DATE + 15 days" +%Y-%m-%d 2>/dev/null || echo "2027-12-31")

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
echo "Follow-up (7-14d): $APPT_FOUND (date=$APPT_DATE), any new: ${ANY_NEW_APPTS:-0}"

# --- Build result JSON ---
RESULT_JSON="{
  \"task\": \"perioperative_appendectomy_management\",
  \"target_patient_id\": $TARGET_PATIENT_ID,
  \"target_patient_name\": \"Luna\",
  \"task_start_date\": \"$TASK_START_DATE\",
  \"k35_found\": $K35_FOUND,
  \"k35_code\": \"$(json_escape "$K35_CODE")\",
  \"k35_active\": $K35_ACTIVE,
  \"any_appendicitis_found\": $ANY_APPENDICITIS_FOUND,
  \"any_appendicitis_code\": \"$(json_escape "$ANY_APPENDICITIS_CODE")\",
  \"evaluation_found\": $EVAL_FOUND,
  \"evaluation_temperature\": \"$(json_escape "$EVAL_TEMP")\",
  \"evaluation_heart_rate\": \"$(json_escape "$EVAL_HR")\",
  \"evaluation_has_fever\": $EVAL_HAS_FEVER,
  \"evaluation_has_tachycardia\": $EVAL_HAS_TACHYCARDIA,
  \"new_lab_count\": ${NEW_LAB_COUNT:-0},
  \"new_lab_types\": \"$(json_escape "$NEW_LAB_TYPES")\",
  \"prescription_found\": $PRESC_FOUND,
  \"antibiotic_found\": $ANTIBIOTIC_FOUND,
  \"antibiotic_name\": \"$(json_escape "$ANTIBIOTIC_NAME")\",
  \"followup_appt_in_range\": $APPT_FOUND,
  \"followup_appt_date\": \"$APPT_DATE\",
  \"followup_window_min\": \"$FOLLOWUP_MIN\",
  \"followup_window_max\": \"$FOLLOWUP_MAX\",
  \"any_new_appt_count\": ${ANY_NEW_APPTS:-0}
}"

safe_write_result "/tmp/perioperative_appendectomy_management_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/perioperative_appendectomy_management_result.json"
echo "=== Export Complete ==="
