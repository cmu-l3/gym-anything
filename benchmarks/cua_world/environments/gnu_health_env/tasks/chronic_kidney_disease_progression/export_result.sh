#!/bin/bash
echo "=== Exporting chronic_kidney_disease_progression result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/ckd_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/ckd_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/ckd_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/ckd_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_LIFESTYLE_MAX=$(cat /tmp/ckd_baseline_lifestyle_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/ckd_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/ckd_target_patient_id 2>/dev/null || echo "0")
TARGET_PARTY_ID=$(cat /tmp/ckd_target_party_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/ckd_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID, party_id: $TARGET_PARTY_ID"

# --- Check 1: N18.x CKD diagnosis (new, active) ---
N18_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'N18%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

N18_FOUND="false"
N18_ACTIVE="false"
N18_CODE="null"
if [ -n "$N18_RECORD" ]; then
    N18_FOUND="true"
    N18_CODE=$(echo "$N18_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$N18_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        N18_ACTIVE="true"
    fi
fi

# Check for stage-specific codes (N18.3 for Stage 3, N18.4 for Stage 4, N18.32 for Stage 3b)
N18_STAGE_SPECIFIC="false"
if [ "$N18_FOUND" = "true" ]; then
    case "$N18_CODE" in
        N18.3*|N18.4*) N18_STAGE_SPECIFIC="true" ;;
    esac
fi

# Any new disease at all
ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "N18 CKD: found=$N18_FOUND code=$N18_CODE active=$N18_ACTIVE stage-specific=$N18_STAGE_SPECIFIC, any new: ${ANY_NEW_DISEASE:-0}"

# --- Check 2: Renal monitoring labs (>= 3) ---
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

# --- Check 3: ACEi/ARB renoprotective prescription ---
PRESC_FOUND="false"
RENOPROT_FOUND="false"
RENOPROT_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    RENO_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%enalapril%'
               OR LOWER(pt.name) LIKE '%ramipril%'
               OR LOWER(pt.name) LIKE '%lisinopril%'
               OR LOWER(pt.name) LIKE '%captopril%'
               OR LOWER(pt.name) LIKE '%losartan%'
               OR LOWER(pt.name) LIKE '%valsartan%'
               OR LOWER(pt.name) LIKE '%irbesartan%'
               OR LOWER(pt.name) LIKE '%candesartan%'
               OR LOWER(pt.name) LIKE '%telmisartan%'
               OR LOWER(pt.name) LIKE '%olmesartan%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$RENO_CHECK" ]; then
        RENOPROT_FOUND="true"
        RENOPROT_NAME="$RENO_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Renoprotective: $RENOPROT_FOUND ($RENOPROT_NAME)"

# --- Check 4: Lifestyle/dietary counseling record ---
LIFESTYLE_RECORD=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_patient_lifestyle
    WHERE (patient_lifestyle = $TARGET_PATIENT_ID OR patient = $TARGET_PATIENT_ID)
      AND id > $BASELINE_LIFESTYLE_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | tr -d '[:space:]')

LIFESTYLE_FOUND="false"
LIFESTYLE_ID="0"
DIET_INFO="none"
if [ -n "$LIFESTYLE_RECORD" ]; then
    LIFESTYLE_FOUND="true"
    LIFESTYLE_ID="$LIFESTYLE_RECORD"

    # Try to get diet/nutrition info from the record
    DIET_CHECK=$(gnuhealth_db_query "
        SELECT COALESCE(
            (SELECT diet FROM gnuhealth_patient_lifestyle WHERE id = $LIFESTYLE_ID LIMIT 1),
            'unknown'
        ) LIMIT 1
    " 2>/dev/null | sed 's/^[[:space:]]*//')
    if [ -n "$DIET_CHECK" ] && [ "$DIET_CHECK" != "unknown" ] && [ "$DIET_CHECK" != "" ]; then
        DIET_INFO="$DIET_CHECK"
    fi
fi
echo "Lifestyle record found: $LIFESTYLE_FOUND (diet=$DIET_INFO)"

# --- Check 5: Nephrology follow-up (80-100 days / ~3 months) ---
FOLLOWUP_MIN=$(date -d "$TASK_START_DATE + 79 days" +%Y-%m-%d 2>/dev/null || echo "2026-01-01")
FOLLOWUP_MAX=$(date -d "$TASK_START_DATE + 101 days" +%Y-%m-%d 2>/dev/null || echo "2027-12-31")

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
echo "Nephrology follow-up (80-100d): $APPT_FOUND (date=$APPT_DATE), any new: ${ANY_NEW_APPTS:-0}"

# --- Build result JSON ---
RESULT_JSON="{
  \"task\": \"chronic_kidney_disease_progression\",
  \"target_patient_id\": $TARGET_PATIENT_ID,
  \"target_party_id\": $TARGET_PARTY_ID,
  \"target_patient_name\": \"Ana Isabel Betz\",
  \"task_start_date\": \"$TASK_START_DATE\",
  \"n18_found\": $N18_FOUND,
  \"n18_code\": \"$(json_escape "$N18_CODE")\",
  \"n18_active\": $N18_ACTIVE,
  \"n18_stage_specific\": $N18_STAGE_SPECIFIC,
  \"any_new_disease_count\": ${ANY_NEW_DISEASE:-0},
  \"new_lab_count\": ${NEW_LAB_COUNT:-0},
  \"new_lab_types\": \"$(json_escape "$NEW_LAB_TYPES")\",
  \"prescription_found\": $PRESC_FOUND,
  \"renoprotective_found\": $RENOPROT_FOUND,
  \"renoprotective_name\": \"$(json_escape "$RENOPROT_NAME")\",
  \"lifestyle_found\": $LIFESTYLE_FOUND,
  \"diet_info\": \"$(json_escape "$DIET_INFO")\",
  \"followup_appt_in_range\": $APPT_FOUND,
  \"followup_appt_date\": \"$APPT_DATE\",
  \"followup_window_min\": \"$FOLLOWUP_MIN\",
  \"followup_window_max\": \"$FOLLOWUP_MAX\",
  \"any_new_appt_count\": ${ANY_NEW_APPTS:-0}
}"

safe_write_result "/tmp/chronic_kidney_disease_progression_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/chronic_kidney_disease_progression_result.json"
echo "=== Export Complete ==="
