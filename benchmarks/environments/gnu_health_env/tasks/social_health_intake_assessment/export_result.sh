#!/bin/bash
echo "=== Exporting social_health_intake_assessment result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/sdoh_final_state.png

# Load baselines
BASELINE_LIFESTYLE_MAX=$(cat /tmp/sdoh_baseline_lifestyle_max 2>/dev/null || echo "0")
BASELINE_FAMILY_DISEASE_MAX=$(cat /tmp/sdoh_baseline_family_disease_max 2>/dev/null || echo "0")
BASELINE_CONTACT_MAX=$(cat /tmp/sdoh_baseline_contact_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/sdoh_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/sdoh_target_patient_id 2>/dev/null || echo "0")
TARGET_PARTY_ID=$(cat /tmp/sdoh_target_party_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/sdoh_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID, party_id: $TARGET_PARTY_ID"

# --- Check 1: Education and Occupation updated ---
EDUCATION_VALUE=$(gnuhealth_db_query "
    SELECT education FROM party_party WHERE id = $TARGET_PARTY_ID
" 2>/dev/null | tr -d '[:space:]')

OCCUPATION_VALUE=$(gnuhealth_db_query "
    SELECT occupation FROM party_party WHERE id = $TARGET_PARTY_ID
" 2>/dev/null | tr -d '[:space:]')

# Occupation might be stored as an ID referencing another table
OCCUPATION_NAME=""
if [ -n "$OCCUPATION_VALUE" ] && [ "$OCCUPATION_VALUE" != "null" ] && echo "$OCCUPATION_VALUE" | grep -qE '^[0-9]+$'; then
    OCCUPATION_NAME=$(gnuhealth_db_query "
        SELECT name FROM gnuhealth_occupation WHERE id = $OCCUPATION_VALUE LIMIT 1
    " 2>/dev/null | tr -d '[:space:]')
else
    OCCUPATION_NAME="$OCCUPATION_VALUE"
fi

EDUCATION_SET="false"
OCCUPATION_SET="false"

if [ -n "$EDUCATION_VALUE" ] && [ "$EDUCATION_VALUE" != "null" ] && [ "$EDUCATION_VALUE" != "" ]; then
    EDUCATION_SET="true"
fi
if [ -n "$OCCUPATION_VALUE" ] && [ "$OCCUPATION_VALUE" != "null" ] && [ "$OCCUPATION_VALUE" != "" ]; then
    OCCUPATION_SET="true"
fi

# Check if university-level (value might be 'u' for university in selection field)
EDUCATION_IS_UNIVERSITY="false"
EDU_LOWER=$(echo "$EDUCATION_VALUE" | tr '[:upper:]' '[:lower:]')
if echo "$EDU_LOWER" | grep -qE 'u|univer|college|tertiary'; then
    EDUCATION_IS_UNIVERSITY="true"
fi

echo "Education value: '$EDUCATION_VALUE' (set=$EDUCATION_SET, university=$EDUCATION_IS_UNIVERSITY)"
echo "Occupation value: '$OCCUPATION_VALUE' / name: '$OCCUPATION_NAME' (set=$OCCUPATION_SET)"

# --- Check 2: Lifestyle record ---
LIFESTYLE_RECORD=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_patient_lifestyle
    WHERE (patient_lifestyle = $TARGET_PATIENT_ID OR patient = $TARGET_PATIENT_ID)
      AND id > $BASELINE_LIFESTYLE_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | tr -d '[:space:]')

LIFESTYLE_FOUND="false"
LIFESTYLE_ACTIVE="false"
LIFESTYLE_NON_SMOKER="false"

if [ -n "$LIFESTYLE_RECORD" ]; then
    LIFESTYLE_FOUND="true"
    LIFESTYLE_ID="$LIFESTYLE_RECORD"

    # Check exercise/physical activity (column might be 'exercise' or 'physical_activity')
    EXERCISE_VAL=$(gnuhealth_db_query "
        SELECT COALESCE(
            (SELECT exercise FROM gnuhealth_patient_lifestyle WHERE id = $LIFESTYLE_ID LIMIT 1),
            (SELECT physical_activity FROM gnuhealth_patient_lifestyle WHERE id = $LIFESTYLE_ID LIMIT 1)
        ) LIMIT 1
    " 2>/dev/null | tr -d '[:space:]')

    # Check smoking (might be 'smoke' or 'tobacco')
    SMOKE_VAL=$(gnuhealth_db_query "
        SELECT COALESCE(
            (SELECT smoke FROM gnuhealth_patient_lifestyle WHERE id = $LIFESTYLE_ID LIMIT 1),
            (SELECT tobacco FROM gnuhealth_patient_lifestyle WHERE id = $LIFESTYLE_ID LIMIT 1)
        ) LIMIT 1
    " 2>/dev/null | tr -d '[:space:]')

    # Active = not sedentary (exercise value is not 'n' or 0)
    EXERCISE_LOWER=$(echo "${EXERCISE_VAL:-}" | tr '[:upper:]' '[:lower:]')
    if [ -n "$EXERCISE_VAL" ] && [ "$EXERCISE_VAL" != "n" ] && [ "$EXERCISE_VAL" != "none" ] && [ "$EXERCISE_VAL" != "0" ] && [ "$EXERCISE_VAL" != "f" ] && [ "$EXERCISE_VAL" != "false" ]; then
        LIFESTYLE_ACTIVE="true"
    fi

    # Non-smoker = false or 'n' for smoke
    if [ "$SMOKE_VAL" = "f" ] || [ "$SMOKE_VAL" = "false" ] || [ "$SMOKE_VAL" = "False" ] || [ "$SMOKE_VAL" = "0" ] || [ -z "$SMOKE_VAL" ]; then
        LIFESTYLE_NON_SMOKER="true"
    fi

    echo "Lifestyle: exercise=$EXERCISE_VAL (active=$LIFESTYLE_ACTIVE), smoke=$SMOKE_VAL (non-smoker=$LIFESTYLE_NON_SMOKER)"
fi
echo "Lifestyle record found: $LIFESTYLE_FOUND"

# --- Check 3: Family history (cardiovascular disease) ---
FAMILY_RECORD=$(gnuhealth_db_query "
    SELECT gfd.id, gpath.code
    FROM gnuhealth_patient_family_diseases gfd
    JOIN gnuhealth_pathology gpath ON gfd.pathology = gpath.id
    WHERE gfd.patient = $TARGET_PATIENT_ID
      AND gfd.id > $BASELINE_FAMILY_DISEASE_MAX
      AND (gpath.code LIKE 'I2%' OR gpath.code LIKE 'I1%')
    ORDER BY gfd.id DESC LIMIT 1
" 2>/dev/null | head -1)

FAMILY_CARDIO_FOUND="false"
FAMILY_CODE="null"
if [ -n "$FAMILY_RECORD" ]; then
    FAMILY_CARDIO_FOUND="true"
    FAMILY_CODE=$(echo "$FAMILY_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi

# Also check any new family disease record (regardless of code)
ANY_FAMILY_NEW=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_family_diseases
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_FAMILY_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Family cardiovascular history found: $FAMILY_CARDIO_FOUND (code=$FAMILY_CODE), any new: ${ANY_FAMILY_NEW:-0}"

# --- Check 4: Phone contact added ---
CONTACT_RECORD=$(gnuhealth_db_query "
    SELECT id, type, value
    FROM party_contact_mechanism
    WHERE party = $TARGET_PARTY_ID
      AND id > $BASELINE_CONTACT_MAX
      AND type IN ('phone', 'mobile', 'other')
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1)

CONTACT_FOUND="false"
CONTACT_VALUE="null"
if [ -n "$CONTACT_RECORD" ]; then
    CONTACT_FOUND="true"
    CONTACT_VALUE=$(echo "$CONTACT_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
fi

# Total contacts for Matt (any type)
ANY_NEW_CONTACT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM party_contact_mechanism
    WHERE party = $TARGET_PARTY_ID AND id > $BASELINE_CONTACT_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Phone contact found: $CONTACT_FOUND, any new contact: ${ANY_NEW_CONTACT:-0}"

# --- Check 5: Preventive care appointment (150-200 days) ---
PREV_MIN=$(date -d "$TASK_START_DATE + 149 days" +%Y-%m-%d 2>/dev/null || echo "2026-01-01")
PREV_MAX=$(date -d "$TASK_START_DATE + 201 days" +%Y-%m-%d 2>/dev/null || echo "2027-12-31")

APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date::text
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
      AND appointment_date::date >= '$PREV_MIN'
      AND appointment_date::date <= '$PREV_MAX'
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DATE="null"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi

ANY_NEW_APPT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_APPT_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Preventive appt (150-200d): $APPT_FOUND (date=$APPT_DATE), any new: ${ANY_NEW_APPT:-0}"

# --- Build result JSON ---
RESULT_JSON="{
  \"task\": \"social_health_intake_assessment\",
  \"target_patient_id\": $TARGET_PATIENT_ID,
  \"target_party_id\": $TARGET_PARTY_ID,
  \"target_patient_name\": \"Matt Zenon Betz\",
  \"task_start_date\": \"$TASK_START_DATE\",
  \"education_value\": \"$(json_escape "$EDUCATION_VALUE")\",
  \"education_set\": $EDUCATION_SET,
  \"education_is_university\": $EDUCATION_IS_UNIVERSITY,
  \"occupation_value\": \"$(json_escape "$OCCUPATION_VALUE")\",
  \"occupation_name\": \"$(json_escape "$OCCUPATION_NAME")\",
  \"occupation_set\": $OCCUPATION_SET,
  \"lifestyle_found\": $LIFESTYLE_FOUND,
  \"lifestyle_active\": $LIFESTYLE_ACTIVE,
  \"lifestyle_non_smoker\": $LIFESTYLE_NON_SMOKER,
  \"family_cardio_found\": $FAMILY_CARDIO_FOUND,
  \"family_disease_code\": \"$(json_escape "$FAMILY_CODE")\",
  \"any_new_family_disease\": ${ANY_FAMILY_NEW:-0},
  \"phone_contact_found\": $CONTACT_FOUND,
  \"contact_value\": \"$(json_escape "$CONTACT_VALUE")\",
  \"any_new_contact_count\": ${ANY_NEW_CONTACT:-0},
  \"preventive_appt_in_range\": $APPT_FOUND,
  \"preventive_appt_date\": \"$APPT_DATE\",
  \"preventive_window_min\": \"$PREV_MIN\",
  \"preventive_window_max\": \"$PREV_MAX\",
  \"any_new_appt_count\": ${ANY_NEW_APPT:-0}
}"

safe_write_result "/tmp/social_health_intake_assessment_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/social_health_intake_assessment_result.json"
echo "=== Export Complete ==="
