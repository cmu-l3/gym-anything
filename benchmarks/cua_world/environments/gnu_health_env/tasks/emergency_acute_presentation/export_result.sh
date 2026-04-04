#!/bin/bash
echo "=== Exporting emergency_acute_presentation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/er_final_state.png

# Load baselines
BASELINE_APPT_MAX=$(cat /tmp/er_baseline_appt_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/er_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/er_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_DISEASE_MAX=$(cat /tmp/er_baseline_disease_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/er_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/er_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Emergency appointment today (or ±1 day) ---
TODAY_START=$(date -d "$TASK_START_DATE - 1 day" +%Y-%m-%d 2>/dev/null || echo "$TASK_START_DATE")
TODAY_END=$(date -d "$TASK_START_DATE + 1 day" +%Y-%m-%d 2>/dev/null || echo "$TASK_START_DATE")

APPT_TODAY=$(gnuhealth_db_query "
    SELECT id, appointment_date::date::text, COALESCE(urgency, 'unknown')
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
      AND appointment_date::date >= '$TODAY_START'
      AND appointment_date::date <= '$TODAY_END'
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1)

ER_APPT_FOUND="false"
ER_APPT_DATE="null"
ER_APPT_URGENCY="unknown"

if [ -n "$APPT_TODAY" ]; then
    ER_APPT_FOUND="true"
    ER_APPT_DATE=$(echo "$APPT_TODAY" | awk -F'|' '{print $2}' | tr -d ' ')
    ER_APPT_URGENCY=$(echo "$APPT_TODAY" | awk -F'|' '{print $3}' | tr -d ' ')
fi
echo "Emergency appointment today: $ER_APPT_FOUND (date=$ER_APPT_DATE, urgency=$ER_APPT_URGENCY)"

# Total new appointments for Luna
ALL_NEW_APPTS=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Total new appointments: ${ALL_NEW_APPTS:-0}"

# --- Check 2: Clinical evaluation with fever and tachycardia ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id, COALESCE(temperature::text,'null'), COALESCE(heart_rate::text,'null'),
           COALESCE(chief_complaint,'')
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1)

EVAL_FOUND="false"
EVAL_TEMP="null"
EVAL_HR="null"
EVAL_CHIEF="null"
EVAL_HAS_FEVER="false"
EVAL_HAS_TACHYCARDIA="false"

if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
    EVAL_TEMP=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    EVAL_CHIEF=$(echo "$EVAL_RECORD" | awk -F'|' '{print $4}')

    # Check fever: temp >= 38.0
    if echo "$EVAL_TEMP" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        FEVER_CHECK=$(echo "$EVAL_TEMP" | awk '{if ($1 >= 38.0) print "true"; else print "false"}')
        EVAL_HAS_FEVER="${FEVER_CHECK:-false}"
    fi

    # Check tachycardia: HR >= 100
    if echo "$EVAL_HR" | grep -qE '^[0-9]+$'; then
        TACHY_CHECK=$(echo "$EVAL_HR" | awk '{if ($1 >= 100) print "true"; else print "false"}')
        EVAL_HAS_TACHYCARDIA="${TACHY_CHECK:-false}"
    fi
fi
echo "Evaluation found: $EVAL_FOUND (temp=$EVAL_TEMP, HR=$EVAL_HR, fever=$EVAL_HAS_FEVER, tachycardia=$EVAL_HAS_TACHYCARDIA)"

# --- Check 3: Lab test orders (count >= 2) ---
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

# --- Check 4: Abdominal ICD-10 diagnosis (K prefix) ---
K_DISEASE=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpd.id > $BASELINE_DISEASE_MAX
      AND gpath.code LIKE 'K%'
    ORDER BY gpd.id DESC LIMIT 1
" 2>/dev/null | head -1)

K_DISEASE_FOUND="false"
K_DISEASE_CODE="null"
if [ -n "$K_DISEASE" ]; then
    K_DISEASE_FOUND="true"
    K_DISEASE_CODE=$(echo "$K_DISEASE" | awk -F'|' '{print $2}' | tr -d ' ')
fi
echo "Abdominal ICD-10 (K code): $K_DISEASE_FOUND (code=$K_DISEASE_CODE)"

# --- Check 5: Short-term surgical/urgent follow-up (within 7 days, excluding today) ---
FOLLOWUP_MAX=$(date -d "$TASK_START_DATE + 7 days" +%Y-%m-%d 2>/dev/null || echo "2027-12-31")
TOMORROW=$(date -d "$TASK_START_DATE + 1 day" +%Y-%m-%d 2>/dev/null || echo "$TASK_START_DATE")

SURGICAL_FOLLOWUP=$(gnuhealth_db_query "
    SELECT id, appointment_date::date::text
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
      AND appointment_date::date >= '$TOMORROW'
      AND appointment_date::date <= '$FOLLOWUP_MAX'
    ORDER BY appointment_date LIMIT 1
" 2>/dev/null | head -1)

SURGICAL_FOUND="false"
SURGICAL_DATE="null"
if [ -n "$SURGICAL_FOLLOWUP" ]; then
    SURGICAL_FOUND="true"
    SURGICAL_DATE=$(echo "$SURGICAL_FOLLOWUP" | awk -F'|' '{print $2}' | tr -d ' ')
fi
echo "Surgical/urgent follow-up (1-7 days): $SURGICAL_FOUND (date=$SURGICAL_DATE)"

# --- Build result JSON ---
RESULT_JSON="{
  \"task\": \"emergency_acute_presentation\",
  \"target_patient_id\": $TARGET_PATIENT_ID,
  \"target_patient_name\": \"Luna\",
  \"task_start_date\": \"$TASK_START_DATE\",
  \"er_appointment_found\": $ER_APPT_FOUND,
  \"er_appointment_date\": \"$ER_APPT_DATE\",
  \"er_appointment_urgency\": \"$(json_escape "$ER_APPT_URGENCY")\",
  \"all_new_appt_count\": ${ALL_NEW_APPTS:-0},
  \"evaluation_found\": $EVAL_FOUND,
  \"evaluation_temperature\": \"$(json_escape "$EVAL_TEMP")\",
  \"evaluation_heart_rate\": \"$(json_escape "$EVAL_HR")\",
  \"evaluation_has_fever\": $EVAL_HAS_FEVER,
  \"evaluation_has_tachycardia\": $EVAL_HAS_TACHYCARDIA,
  \"new_lab_count\": ${NEW_LAB_COUNT:-0},
  \"new_lab_types\": \"$(json_escape "$NEW_LAB_TYPES")\",
  \"abdominal_diagnosis_found\": $K_DISEASE_FOUND,
  \"abdominal_diagnosis_code\": \"$(json_escape "$K_DISEASE_CODE")\",
  \"surgical_followup_found\": $SURGICAL_FOUND,
  \"surgical_followup_date\": \"$SURGICAL_DATE\",
  \"followup_max_window\": \"$FOLLOWUP_MAX\"
}"

safe_write_result "/tmp/emergency_acute_presentation_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/emergency_acute_presentation_result.json"
echo "=== Export Complete ==="
