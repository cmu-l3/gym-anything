#!/bin/bash
echo "=== Exporting occupational_benzene_hematotoxicity result ==="

source /workspace/scripts/task_utils.sh

# Take final evidence screenshot
take_screenshot /tmp/task_final.png

# Load baselines
BASELINE_DISEASE_MAX=$(cat /tmp/benz_baseline_disease_max 2>/dev/null || echo "0")
BASELINE_EVAL_MAX=$(cat /tmp/benz_baseline_eval_max 2>/dev/null || echo "0")
BASELINE_PRESCRIPTION_MAX=$(cat /tmp/benz_baseline_prescription_max 2>/dev/null || echo "0")
BASELINE_LAB_MAX=$(cat /tmp/benz_baseline_lab_max 2>/dev/null || echo "0")
BASELINE_APPT_MAX=$(cat /tmp/benz_baseline_appt_max 2>/dev/null || echo "0")
TARGET_PATIENT_ID=$(cat /tmp/benz_target_patient_id 2>/dev/null || echo "0")
TASK_START_DATE=$(cat /tmp/benz_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Target patient_id: $TARGET_PATIENT_ID"

# --- Check 1: Benzene toxicity or Aplastic Anemia Diagnosis (new, active) ---
DIAG_RECORD=$(gnuhealth_db_query "
    SELECT gpd.id, gpath.code, gpd.is_active::text
    FROM gnuhealth_patient_disease gpd
    JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
    WHERE gpd.patient = $TARGET_PATIENT_ID
      AND (gpath.code LIKE 'T52%' OR gpath.code LIKE 'D61%')
      AND gpd.id > $BASELINE_DISEASE_MAX
    ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

DIAG_FOUND="false"
DIAG_ACTIVE="false"
DIAG_CODE="null"
if [ -n "$DIAG_RECORD" ]; then
    DIAG_FOUND="true"
    DIAG_CODE=$(echo "$DIAG_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    ACTIVE_VAL=$(echo "$DIAG_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        DIAG_ACTIVE="true"
    fi
fi

ANY_NEW_DISEASE=$(gnuhealth_db_query "
    SELECT COUNT(*) FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID AND id > $BASELINE_DISEASE_MAX
" 2>/dev/null | tr -d '[:space:]')
echo "Target Diagnosis (T52/D61): found=$DIAG_FOUND code=$DIAG_CODE active=$DIAG_ACTIVE, any new: ${ANY_NEW_DISEASE:-0}"


# --- Check 2: Clinical evaluation ---
EVAL_RECORD=$(gnuhealth_db_query "
    SELECT id
    FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_EVAL_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

EVAL_FOUND="false"
if [ -n "$EVAL_RECORD" ]; then
    EVAL_FOUND="true"
fi
echo "Clinical Evaluation: found=$EVAL_FOUND"


# --- Check 3: Lab orders (>= 3) ---
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


# --- Check 4: Supportive prescription ---
PRESC_FOUND="false"
SUPPORT_FOUND="false"
SUPPORT_DRUG_NAME="none"

NEW_PRESC_ID=$(gnuhealth_db_query "
    SELECT id FROM gnuhealth_prescription_order
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_PRESCRIPTION_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | tr -d '[:space:]')

if [ -n "$NEW_PRESC_ID" ]; then
    PRESC_FOUND="true"

    SUPPORT_CHECK=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_order_line pol ON pol.name = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.name = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $TARGET_PATIENT_ID
          AND po.id > $BASELINE_PRESCRIPTION_MAX
          AND (LOWER(pt.name) LIKE '%folic%'
               OR LOWER(pt.name) LIKE '%vitamin%'
               OR LOWER(pt.name) LIKE '%ferrous%'
               OR LOWER(pt.name) LIKE '%iron%'
               OR LOWER(pt.name) LIKE '%b12%'
               OR LOWER(pt.name) LIKE '%cyanocobalamin%')
        LIMIT 1
    " 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')

    if [ -n "$SUPPORT_CHECK" ]; then
        SUPPORT_FOUND="true"
        SUPPORT_DRUG_NAME="$SUPPORT_CHECK"
    fi
fi
echo "Prescription found: $PRESC_FOUND, Supportive: $SUPPORT_FOUND ($SUPPORT_DRUG_NAME)"


# --- Check 5: Follow-up Appointment (7-14 days) ---
APPT_RECORD=$(gnuhealth_db_query "
    SELECT id, appointment_date::date
    FROM gnuhealth_appointment
    WHERE patient = $TARGET_PATIENT_ID
      AND id > $BASELINE_APPT_MAX
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

APPT_FOUND="false"
APPT_DAYS="0"
if [ -n "$APPT_RECORD" ]; then
    APPT_FOUND="true"
    APPT_DATE=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    APPT_DAYS=$(gnuhealth_db_query "SELECT '$APPT_DATE'::date - '$TASK_START_DATE'::date" | tr -d '[:space:]')
fi
echo "Appointment found: $APPT_FOUND, days offset: $APPT_DAYS"


# Retrieve correct patient name to cross-check in Python
TARGET_NAME=$(gnuhealth_db_query "
    SELECT CONCAT(name, ' ', lastname) FROM party_party
    WHERE id = (SELECT party FROM gnuhealth_patient WHERE id = $TARGET_PATIENT_ID)
" 2>/dev/null | tr -d '\n')


# Build JSON Export
TEMP_JSON=$(mktemp /tmp/benz_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_patient_id": ${TARGET_PATIENT_ID:-0},
    "target_patient_name": "$TARGET_NAME",
    "diag_found": $DIAG_FOUND,
    "diag_code": "$DIAG_CODE",
    "diag_active": $DIAG_ACTIVE,
    "any_new_disease_count": ${ANY_NEW_DISEASE:-0},
    "eval_found": $EVAL_FOUND,
    "new_lab_count": ${NEW_LAB_COUNT:-0},
    "new_lab_types": "$NEW_LAB_TYPES",
    "presc_found": $PRESC_FOUND,
    "support_found": $SUPPORT_FOUND,
    "support_drug": "$SUPPORT_DRUG_NAME",
    "appt_found": $APPT_FOUND,
    "appt_days": ${APPT_DAYS:-0}
}
EOF

# Use safe permission write logic
rm -f /tmp/occupational_benzene_hematotoxicity_result.json 2>/dev/null || sudo rm -f /tmp/occupational_benzene_hematotoxicity_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/occupational_benzene_hematotoxicity_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/occupational_benzene_hematotoxicity_result.json
chmod 666 /tmp/occupational_benzene_hematotoxicity_result.json 2>/dev/null || sudo chmod 666 /tmp/occupational_benzene_hematotoxicity_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export Complete. Verification JSON written to /tmp/occupational_benzene_hematotoxicity_result.json"
cat /tmp/occupational_benzene_hematotoxicity_result.json