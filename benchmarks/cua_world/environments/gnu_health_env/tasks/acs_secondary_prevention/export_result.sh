#!/bin/bash
echo "=== Exporting acs_secondary_prevention result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/acs_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/acs_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/acs_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/acs_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_LIFESTYLE_MAX=$(cat /tmp/acs_baseline_lifestyle_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/acs_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/acs_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/acs_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Cardiac Diagnosis (I21 or I25) ---
CARDIAC_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'I21%' OR gpath.code LIKE 'I25%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

CARDIAC_FOUND="false"
CARDIAC_ACTIVE="false"
CARDIAC_CODE="null"
if [ -n "$CARDIAC_RECORD" ]; then
    CARDIAC_FOUND="true"
    CARDIAC_CODE=$(echo "$CARDIAC_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$CARDIAC_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        CARDIAC_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 2: Secondary Prevention Rx (Antiplatelet, Statin, Beta-blocker) ---
HAS_ANTIPLATELET=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_prescription_order po
    JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
    JOIN gnuhealth_medicament med ON pol.medicament = med.id
    JOIN product_product pp ON med.name = pp.id
    JOIN product_template pt ON pp.template = pt.id
    WHERE po.patient = $TARGET_PATIENT_ID AND po.id > $BASELINE_PRESCRIPTION_MAX
      AND (LOWER(pt.name) LIKE '%aspirin%' OR LOWER(pt.name) LIKE '%acetylsalicylic%')
" 2>/dev/null | tr -d '[:space:]')

HAS_STATIN=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_prescription_order po
    JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
    JOIN gnuhealth_medicament med ON pol.medicament = med.id
    JOIN product_product pp ON med.name = pp.id
    JOIN product_template pt ON pp.template = pt.id
    WHERE po.patient = $TARGET_PATIENT_ID AND po.id > $BASELINE_PRESCRIPTION_MAX
      AND (LOWER(pt.name) LIKE '%statin%')
" 2>/dev/null | tr -d '[:space:]')

HAS_BETABLOCKER=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_prescription_order po
    JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
    JOIN gnuhealth_medicament med ON pol.medicament = med.id
    JOIN product_product pp ON med.name = pp.id
    JOIN product_template pt ON pp.template = pt.id
    WHERE po.patient = $TARGET_PATIENT_ID AND po.id > $BASELINE_PRESCRIPTION_MAX
      AND (LOWER(pt.name) LIKE '%metoprolol%' OR LOWER(pt.name) LIKE '%bisoprolol%' OR LOWER(pt.name) LIKE '%carvedilol%' OR LOWER(pt.name) LIKE '%atenolol%')
" 2>/dev/null | tr -d '[:space:]')

# --- Check 3: Lipid monitoring labs ---
NEW_LIPID_LABS_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*)
    FROM gnuhealth_patient_lab_test glt
    JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
    WHERE glt.patient_id = $TARGET_PATIENT_ID
      AND glt.id > $BASELINE_LAB_MAX
      AND (LOWER(ltt.name) LIKE '%lipid%' 
           OR LOWER(ltt.name) LIKE '%cholesterol%' 
           OR LOWER(ltt.name) LIKE '%triglyceride%' 
           OR LOWER(ltt.name) LIKE '%hdl%' 
           OR LOWER(ltt.name) LIKE '%ldl%')
" 2>/dev/null | tr -d '[:space:]')

# --- Check 4: Lifestyle counseling (smoking/diet) ---
LIFESTYLE_RECORD=$(gnuhealth_db_query "
    SELECT info
    FROM gnuhealth_patient_lifestyle
    WHERE (patient_lifestyle = $TARGET_PATIENT_ID OR patient = $TARGET_PATIENT_ID)
      AND id > $BASELINE_LIFESTYLE_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null)

LIFESTYLE_FOUND="false"
LIFESTYLE_HAS_SMOKING="false"
LIFESTYLE_HAS_DIET="false"
if [ -n "$LIFESTYLE_RECORD" ]; then
    LIFESTYLE_FOUND="true"
    if echo "$LIFESTYLE_RECORD" | grep -qiE 'smok|tobacco'; then
        LIFESTYLE_HAS_SMOKING="true"
    fi
    if echo "$LIFESTYLE_RECORD" | grep -qiE 'diet|cardiac|heart|sodium|salt|nutrition'; then
        LIFESTYLE_HAS_DIET="true"
    fi
fi

# --- Check 5: Appointment (21-35 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1
" 2>/dev/null | tr -d '[:space:]')

APPT_FOUND="false"
APPT_DATE="null"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE="$APPT_RECORD"
fi

# Build JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "Roberto Carlos",
    "task_start_date": "$TASK_START_DATE",
    "cardiac_found": $CARDIAC_FOUND,
    "cardiac_active": $CARDIAC_ACTIVE,
    "cardiac_code": "$CARDIAC_CODE",
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "has_antiplatelet": $( [ "${HAS_ANTIPLATELET:-0}" -gt 0 ] && echo "true" || echo "false" ),
    "has_statin": $( [ "${HAS_STATIN:-0}" -gt 0 ] && echo "true" || echo "false" ),
    "has_betablocker": $( [ "${HAS_BETABLOCKER:-0}" -gt 0 ] && echo "true" || echo "false" ),
    "new_lipid_labs_count": ${NEW_LIPID_LABS_COUNT:-0},
    "lifestyle_found": $LIFESTYLE_FOUND,
    "lifestyle_has_smoking": $LIFESTYLE_HAS_SMOKING,
    "lifestyle_has_diet": $LIFESTYLE_HAS_DIET,
    "appt_found": $APPT_FOUND,
    "appt_date": "$APPT_DATE"
}
EOF

rm -f /tmp/acs_secondary_prevention_result.json 2>/dev/null || sudo rm -f /tmp/acs_secondary_prevention_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/acs_secondary_prevention_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/acs_secondary_prevention_result.json
chmod 666 /tmp/acs_secondary_prevention_result.json 2>/dev/null || sudo chmod 666 /tmp/acs_secondary_prevention_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/acs_secondary_prevention_result.json"
cat /tmp/acs_secondary_prevention_result.json
echo "=== Export Complete ==="