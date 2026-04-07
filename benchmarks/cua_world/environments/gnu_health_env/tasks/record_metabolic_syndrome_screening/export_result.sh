#!/bin/bash
echo "=== Exporting record_metabolic_syndrome_screening result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/metabolic_final_state.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/metabolic_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/metabolic_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/metabolic_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_LIFESTYLE_MAX=$(cat /tmp/metabolic_baseline_lifestyle_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/metabolic_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/metabolic_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/metabolic_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Diagnoses (E11, I10, E78) ---
E11_RECORD=$(gnuhealth_db_query "
    SELECT gpd.is_active::text, gpath.code
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'E11%' OR gpath.code LIKE 'E14%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

I10_RECORD=$(gnuhealth_db_query "
    SELECT gpd.is_active::text, gpath.code
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'I10%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

E78_RECORD=$(gnuhealth_db_query "
    SELECT gpd.is_active::text, gpath.code
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND gpath.code LIKE 'E78%'
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

E11_FOUND="false"
E11_ACTIVE="false"
if [ -n "$E11_RECORD" ]; then
    E11_FOUND="true"
    ACTIVE_VAL=$(echo "$E11_RECORD" | awk -F'|' '{print $1}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then E11_ACTIVE="true"; fi
fi

I10_FOUND="false"
I10_ACTIVE="false"
if [ -n "$I10_RECORD" ]; then
    I10_FOUND="true"
    ACTIVE_VAL=$(echo "$I10_RECORD" | awk -F'|' '{print $1}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then I10_ACTIVE="true"; fi
fi

E78_FOUND="false"
E78_ACTIVE="false"
if [ -n "$E78_RECORD" ]; then
    E78_FOUND="true"
    ACTIVE_VAL=$(echo "$E78_RECORD" | awk -F'|' '{print $1}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then E78_ACTIVE="true"; fi
fi

# --- Check 2: Prescriptions (Metformin, AntiHTN, Statin) ---
METFORMIN_FOUND="false"
ANTIHTN_FOUND="false"
STATIN_FOUND="false"

# Query all new prescription lines for this patient
PRESC_LINES=$(gnuhealth_db_query "
    SELECT LOWER(pt.name)
    FROM gnuhealth_prescription_order po
    JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
    JOIN gnuhealth_medicament med ON pol.medicament = med.id
    JOIN product_product pp ON med.name = pp.id
    JOIN product_template pt ON pp.template = pt.id
    WHERE po.patient = $TARGET_PATIENT_ID
      AND po.id > $BASELINE_PRESCRIPTION_MAX
" 2>/dev/null)

while IFS= read -r drug; do
    if [ -z "$drug" ]; then continue; fi
    # Metformin check
    if echo "$drug" | grep -q "metformin"; then
        METFORMIN_FOUND="true"
    fi
    # AntiHTN check
    if echo "$drug" | grep -qE "enalapril|ramipril|lisinopril|captopril|losartan|valsartan|irbesartan|amlodipine|nifedipine|diltiazem"; then
        ANTIHTN_FOUND="true"
    fi
    # Statin check
    if echo "$drug" | grep -qE "atorvastatin|rosuvastatin|simvastatin|pravastatin|lovastatin"; then
        STATIN_FOUND="true"
    fi
done <<< "$PRESC_LINES"

# --- Check 3: Lab orders (>= 3) ---
NEW_LAB_COUNT=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_lab_test
    WHERE patient_id = $TARGET_PATIENT_ID
      AND id > $BASELINE_LAB_MAX
" 2>/dev/null | tr -d '[:space:]')

# --- Check 4: Lifestyle/Dietary counseling ---
LIFESTYLE_RECORD=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_patient_lifestyle
    WHERE (patient_lifestyle = $TARGET_PATIENT_ID OR patient = $TARGET_PATIENT_ID)
      AND id > $BASELINE_LIFESTYLE_MAX
    LIMIT 1" 2>/dev/null | tr -d '[:space:]')

LIFESTYLE_FOUND="false"
if [ -n "$LIFESTYLE_RECORD" ]; then
    LIFESTYLE_FOUND="true"
fi

# --- Check 5: Follow-up Appointment (60-120 days) ---
APPT_DAYS=-1
APPT_RECORD=$(gnuhealth_db_query "
    SELECT appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$APPT_RECORD" ]; then
    START_SEC=$(date -d "$TASK_START_DATE" +%s)
    APPT_SEC=$(date -d "$APPT_RECORD" +%s 2>/dev/null || echo "$START_SEC")
    APPT_DAYS=$(( (APPT_SEC - START_SEC) / 86400 ))
fi

# Retrieve patient name to confirm correct target
TARGET_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(pp.name, ' ', pp.lastname)
    FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id
    WHERE gp.id = $TARGET_PATIENT_ID LIMIT 1" 2>/dev/null)

# Generate JSON securely
TEMP_JSON=$(mktemp /tmp/metabolic_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": $TARGET_PATIENT_ID,
    "target_patient_name": "$(json_escape "$TARGET_NAME")",
    "e11_found": $E11_FOUND,
    "e11_active": $E11_ACTIVE,
    "i10_found": $I10_FOUND,
    "i10_active": $I10_ACTIVE,
    "e78_found": $E78_FOUND,
    "e78_active": $E78_ACTIVE,
    "metformin_found": $METFORMIN_FOUND,
    "antihtn_found": $ANTIHTN_FOUND,
    "statin_found": $STATIN_FOUND,
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "lifestyle_found": $LIFESTYLE_FOUND,
    "appointment_days_diff": $APPT_DAYS
}
EOF

safe_write_result "/tmp/record_metabolic_syndrome_screening_result.json" "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/record_metabolic_syndrome_screening_result.json