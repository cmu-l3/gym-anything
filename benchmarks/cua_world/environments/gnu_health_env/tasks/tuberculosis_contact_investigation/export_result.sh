#!/bin/bash
echo "=== Exporting tuberculosis_contact_investigation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/tb_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/tb_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/tb_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/tb_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_FAMILY_MAX=$(cat /tmp/tb_baseline_family_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/tb_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/tb_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/tb_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: A15.x TB diagnosis (new, active) ---
A15_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'A15%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

A15_FOUND="false"
A15_ACTIVE="false"
A15_CODE="null"
if [ -n "$A15_RECORD" ]; then
    A15_FOUND="true"
    A15_CODE=$(echo "$A15_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$A15_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        A15_ACTIVE="true"
    fi
fi

# Also check broader TB codes (A16, A19)
ANY_TB=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'A15%' OR gpath.code LIKE 'A16%' OR gpath.code LIKE 'A19%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

ANY_TB_FOUND="false"
ANY_TB_CODE="null"
if [ -n "$ANY_TB" ]; then
    ANY_TB_FOUND="true"
    ANY_TB_CODE=$(echo "$ANY_TB" | awk -F'|' '{print $2}' | tr -d ' ')
fi
echo "A15 found: $A15_FOUND (code=$A15_CODE, active=$A15_ACTIVE), any TB: $ANY_TB_FOUND ($ANY_TB_CODE)"

# --- Check 2: RIPE regimen prescriptions (count drugs matched) ---
RIPE_COUNT=0
RIPE_DRUGS_FOUND=""

# Count each RIPE drug independently
for DRUG_PATTERN in "rifamp%\|rifabutin%" "isoniazid%\|inh%" "pyrazinamid%" "ethambutol%"; do
    # Build SQL-friendly pattern
    SQL_PATTERNS=""
    OLDIFS="$IFS"
    IFS='\|'
    for pat in $DRUG_PATTERN; do
        if [ -n "$SQL_PATTERNS" ]; then
            SQL_PATTERNS="$SQL_PATTERNS OR LOWER(pt.name) LIKE '$pat'"
        else
            SQL_PATTERNS="LOWER(pt.name) LIKE '$pat'"
        fi
    done
    IFS="$OLDIFS"

    DRUG_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND ($SQL_PATTERNS)
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$DRUG_CHECK" ]; then
        RIPE_COUNT=$((RIPE_COUNT + 1))
        if [ -n "$RIPE_DRUGS_FOUND" ]; then
            RIPE_DRUGS_FOUND="$RIPE_DRUGS_FOUND, $DRUG_CHECK"
        else
            RIPE_DRUGS_FOUND="$DRUG_CHECK"
        fi
    fi
done

# Total new prescriptions
TOTAL_NEW_PRESC=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_PRESCRIPTION_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "RIPE drugs found: $RIPE_COUNT ($RIPE_DRUGS_FOUND), total new prescriptions: ${TOTAL_NEW_PRESC:-0}"

# --- Check 3: Sputum/AFB lab orders (>= 2) ---
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

# --- Check 4: Family disease history (TB contact) ---
FAMILY_RECORD=$(gnuhealth_db_query "
    SELECT gfd.id, gpath.code
    FROM gnuhealth_patient_family_diseases gfd
    JOIN gnuhealth_pathology gpath ON gfd.pathology = gpath.id
    WHERE gfd.patient = $TARGET_PATIENT_ID
      AND gfd.id > $BASELINE_FAMILY_MAX
      AND (gpath.code LIKE 'A15%' OR gpath.code LIKE 'A16%' OR gpath.code LIKE 'Z20%'
           OR gpath.code LIKE 'A19%' OR gpath.code LIKE 'Z03%')
    ORDER BY gfd.id DESC LIMIT 1" 2>/dev/null | head -1)

FAMILY_TB_FOUND="false"
FAMILY_TB_CODE="null"
if [ -n "$FAMILY_RECORD" ]; then
    FAMILY_TB_FOUND="true"
    FAMILY_TB_CODE=$(echo "$FAMILY_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
fi

# Any new family disease at all
ANY_FAMILY_NEW=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_family_diseases
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_FAMILY_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Family TB contact: $FAMILY_TB_FOUND (code=$FAMILY_TB_CODE), any new family: ${ANY_FAMILY_NEW:-0}"

# --- Check 5: Treatment follow-up (10-21 days) ---
FOLLOWUP_MIN=$(date -d "$TASK_START_DATE + 9 days" +%Y-%m-%d 2>/dev/null || echo "2026-01-01")
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
echo "Treatment follow-up (10-21d): $APPT_FOUND (date=$APPT_DATE), any new: ${ANY_NEW_APPTS:-0}"

# --- Build result JSON ---
RESULT_JSON="{
  \"task\": \"tuberculosis_contact_investigation\",
  \"target_patient_id\": $TARGET_PATIENT_ID,
  \"target_patient_name\": \"Matt Zenon Betz\",
  \"task_start_date\": \"$TASK_START_DATE\",
  \"a15_found\": $A15_FOUND,
  \"a15_code\": \"$(json_escape "$A15_CODE")\",
  \"a15_active\": $A15_ACTIVE,
  \"any_tb_found\": $ANY_TB_FOUND,
  \"any_tb_code\": \"$(json_escape "$ANY_TB_CODE")\",
  \"ripe_drug_count\": $RIPE_COUNT,
  \"ripe_drugs_found\": \"$(json_escape "$RIPE_DRUGS_FOUND")\",
  \"total_new_prescriptions\": ${TOTAL_NEW_PRESC:-0},
  \"new_lab_count\": ${NEW_LAB_COUNT:-0},
  \"new_lab_types\": \"$(json_escape "$NEW_LAB_TYPES")\",
  \"family_tb_contact_found\": $FAMILY_TB_FOUND,
  \"family_tb_code\": \"$(json_escape "$FAMILY_TB_CODE")\",
  \"any_new_family_disease\": ${ANY_FAMILY_NEW:-0},
  \"followup_appt_in_range\": $APPT_FOUND,
  \"followup_appt_date\": \"$APPT_DATE\",
  \"followup_window_min\": \"$FOLLOWUP_MIN\",
  \"followup_window_max\": \"$FOLLOWUP_MAX\",
  \"any_new_appt_count\": ${ANY_NEW_APPTS:-0}
}"

safe_write_result "/tmp/tuberculosis_contact_investigation_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/tuberculosis_contact_investigation_result.json"
echo "=== Export Complete ==="
