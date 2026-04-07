#!/bin/bash
echo "=== Exporting occupational_lead_exposure_full_intake result ==="

source /workspace/scripts/task_utils.sh

PREFIX="occl"

# Take final screenshot
take_screenshot /tmp/${PREFIX}_final_state.png

# ────────────────────────────────────────────────────────
# Load baselines
# ────────────────────────────────────────────────────────
read_bl() { cat "/tmp/${PREFIX}_baseline_${1}_max" 2>/dev/null || echo "0"; }

BL_LAB_TYPE=$(read_bl gnuhealth_lab_test_type)
BL_CRITERIA=$(read_bl gnuhealth_lab_test_critearea)
BL_PATIENT=$(read_bl gnuhealth_patient)
BL_PARTY=$(read_bl party_party)
BL_DISEASE=$(read_bl gnuhealth_patient_disease)
BL_EVAL=$(read_bl gnuhealth_patient_evaluation)
# Note: allergies are stored in gnuhealth_patient_disease (is_allergy=true), using BL_DISEASE
BL_LAB=$(read_bl gnuhealth_patient_lab_test)
BL_PRESC=$(read_bl gnuhealth_prescription_order)
BL_APPT=$(read_bl gnuhealth_appointment)

FAMILY_TABLE=$(cat /tmp/${PREFIX}_family_table 2>/dev/null || echo "gnuhealth_family_disease")
BL_FAMILY=$(read_bl "$FAMILY_TABLE")

TASK_START_DATE=$(cat /tmp/${PREFIX}_task_start_date 2>/dev/null || date +%Y-%m-%d)

echo "Baselines loaded."

# ────────────────────────────────────────────────────────
# CHECK 1: BLL_PANEL Lab Test Type
# ────────────────────────────────────────────────────────
LAB_TYPE_RECORD=$(gnuhealth_db_query "
    SELECT id, name, code, active::text
    FROM gnuhealth_lab_test_type
    WHERE id > $BL_LAB_TYPE
      AND (code = 'BLL_PANEL' OR UPPER(name) LIKE '%BLOOD LEAD%')
    ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

LAB_TYPE_FOUND="false"
LAB_TYPE_NAME="none"
LAB_TYPE_ACTIVE="false"
LAB_TYPE_ID=""

if [ -n "$LAB_TYPE_RECORD" ]; then
    LAB_TYPE_FOUND="true"
    LAB_TYPE_ID=$(echo "$LAB_TYPE_RECORD" | awk -F'|' '{print $1}' | tr -d ' ')
    LAB_TYPE_NAME=$(echo "$LAB_TYPE_RECORD" | awk -F'|' '{print $2}')
    ACTIVE_VAL=$(echo "$LAB_TYPE_RECORD" | awk -F'|' '{print $4}' | tr -d ' ')
    if [ "$ACTIVE_VAL" = "t" ] || [ "$ACTIVE_VAL" = "true" ] || [ "$ACTIVE_VAL" = "True" ]; then
        LAB_TYPE_ACTIVE="true"
    fi
fi

# CHECK 2: Analytes/Criteria for BLL_PANEL
CRITERIA_COUNT="0"
CRITERIA_NAMES="none"
if [ -n "$LAB_TYPE_ID" ]; then
    CRITERIA_COUNT=$(gnuhealth_db_query "
        SELECT COUNT(*) FROM gnuhealth_lab_test_critearea
        WHERE test_type_id = $LAB_TYPE_ID AND id > $BL_CRITERIA" | tr -d '[:space:]')
    CRITERIA_NAMES=$(gnuhealth_db_query "
        SELECT CONCAT(name, ':', COALESCE(code,''))
        FROM gnuhealth_lab_test_critearea
        WHERE test_type_id = $LAB_TYPE_ID AND id > $BL_CRITERIA" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
fi
echo "Lab type: found=$LAB_TYPE_FOUND name=$LAB_TYPE_NAME active=$LAB_TYPE_ACTIVE criteria=$CRITERIA_COUNT ($CRITERIA_NAMES)"

# ────────────────────────────────────────────────────────
# FIND THE TARGET PATIENT (created by the agent)
# ────────────────────────────────────────────────────────
PATIENT_PARTY_ID=$(gnuhealth_db_query "
    SELECT id FROM party_party
    WHERE id > $BL_PARTY
      AND name ILIKE '%Marcus%' AND lastname ILIKE '%Torres%'
    LIMIT 1" | tr -d '[:space:]')

PATIENT_ID=""
PATIENT_FOUND="false"
if [ -n "$PATIENT_PARTY_ID" ]; then
    PATIENT_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_patient
        WHERE party = $PATIENT_PARTY_ID
        LIMIT 1" | tr -d '[:space:]')
    if [ -n "$PATIENT_ID" ]; then
        PATIENT_FOUND="true"
    fi
fi
echo "Patient Marcus Torres: found=$PATIENT_FOUND id=$PATIENT_ID party=$PATIENT_PARTY_ID"

# ────────────────────────────────────────────────────────
# CHECK 3: Diagnoses (T56, D64, I10)
# ────────────────────────────────────────────────────────
DISEASE_CODES="none"
DISEASE_COUNT="0"
HAS_T56="false"
HAS_D64="false"
HAS_I10="false"

if [ -n "$PATIENT_ID" ]; then
    DISEASE_RECORDS=$(gnuhealth_db_query "
        SELECT gpath.code
        FROM gnuhealth_patient_disease gpd
        JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
        WHERE gpd.patient = $PATIENT_ID
          AND gpd.id > $BL_DISEASE" 2>/dev/null)

    DISEASE_COUNT=$(echo "$DISEASE_RECORDS" | grep -c '[A-Z]' || echo "0")
    DISEASE_CODES=$(echo "$DISEASE_RECORDS" | tr '\n' ',' | sed 's/,$//' | tr -d ' ')

    if echo "$DISEASE_RECORDS" | grep -qi "T56"; then HAS_T56="true"; fi
    if echo "$DISEASE_RECORDS" | grep -qi "D64"; then HAS_D64="true"; fi
    if echo "$DISEASE_RECORDS" | grep -qi "I10"; then HAS_I10="true"; fi
fi
echo "Diagnoses: count=$DISEASE_COUNT codes=$DISEASE_CODES T56=$HAS_T56 D64=$HAS_D64 I10=$HAS_I10"

# ────────────────────────────────────────────────────────
# CHECK 4: Penicillin Allergy (stored in gnuhealth_patient_disease with is_allergy=true)
# ────────────────────────────────────────────────────────
ALLERGY_FOUND="false"
ALLERGY_ALLERGEN="none"
ALLERGY_SEVERITY="unknown"

if [ -n "$PATIENT_ID" ]; then
    # In GNU Health 5.0, allergies are diseases with is_allergy=true
    ALLERGY_RECORD=$(gnuhealth_db_query "
        SELECT gpd.id, gpath.name, COALESCE(gpd.disease_severity, 'unknown'), gpd.allergy_type
        FROM gnuhealth_patient_disease gpd
        JOIN gnuhealth_pathology gpath ON gpd.pathology = gpath.id
        WHERE gpd.patient = $PATIENT_ID
          AND gpd.id > $BL_DISEASE
          AND gpd.is_allergy = true
          AND (LOWER(gpath.name) LIKE '%penicillin%' OR LOWER(gpath.code) LIKE '%penicillin%'
               OR LOWER(gpd.short_comment) LIKE '%penicillin%' OR LOWER(gpd.extra_info) LIKE '%penicillin%')
        ORDER BY gpd.id DESC LIMIT 1" 2>/dev/null | head -1)

    if [ -n "$ALLERGY_RECORD" ]; then
        ALLERGY_FOUND="true"
        ALLERGY_ALLERGEN=$(echo "$ALLERGY_RECORD" | awk -F'|' '{print $2}')
        ALLERGY_SEVERITY=$(echo "$ALLERGY_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
    fi

    # Fallback: any allergy disease at all for this patient
    ANY_ALLERGY=$(gnuhealth_db_query "
        SELECT COUNT(*) FROM gnuhealth_patient_disease
        WHERE patient = $PATIENT_ID AND id > $BL_DISEASE AND is_allergy = true" | tr -d '[:space:]')
fi
echo "Allergy: found=$ALLERGY_FOUND allergen=$ALLERGY_ALLERGEN severity=$ALLERGY_SEVERITY any_new=${ANY_ALLERGY:-0}"

# ────────────────────────────────────────────────────────
# CHECK 5: Family History
# ────────────────────────────────────────────────────────
FAMILY_COUNT="0"
FAMILY_ROWS_JSON=""
HAS_FATHER="false"
HAS_MOTHER="false"
HAS_I25="false"
HAS_E11="false"

if [ -n "$PATIENT_ID" ]; then
    FAMILY_COUNT=$(gnuhealth_db_query "
        SELECT COUNT(*) FROM $FAMILY_TABLE
        WHERE patient = $PATIENT_ID AND id > $BL_FAMILY" | tr -d '[:space:]')

    FAMILY_ROWS_JSON=$(gnuhealth_db_query "
        SELECT row_to_json(t)::text
        FROM (SELECT * FROM $FAMILY_TABLE WHERE patient = $PATIENT_ID AND id > $BL_FAMILY) t" 2>/dev/null)

    # Check for relative types
    if echo "$FAMILY_ROWS_JSON" | grep -qiE "father|paternal"; then HAS_FATHER="true"; fi
    if echo "$FAMILY_ROWS_JSON" | grep -qiE "mother|maternal"; then HAS_MOTHER="true"; fi

    # Check for pathology codes by resolving IDs
    I25_PATH_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_pathology WHERE code LIKE 'I25%' LIMIT 1" | tr -d '[:space:]')
    E11_PATH_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_pathology WHERE code='E11' LIMIT 1" | tr -d '[:space:]')

    if [ -n "$I25_PATH_ID" ] && echo "$FAMILY_ROWS_JSON" | grep -qE "(:$I25_PATH_ID[,}]|: $I25_PATH_ID[,}])"; then HAS_I25="true"; fi
    if [ -n "$E11_PATH_ID" ] && echo "$FAMILY_ROWS_JSON" | grep -qE "(:$E11_PATH_ID[,}]|: $E11_PATH_ID[,}])"; then HAS_E11="true"; fi
fi
echo "Family history: count=$FAMILY_COUNT father=$HAS_FATHER mother=$HAS_MOTHER I25=$HAS_I25 E11=$HAS_E11"

# ────────────────────────────────────────────────────────
# CHECK 6: Health Evaluation (vitals)
# ────────────────────────────────────────────────────────
EVAL_FOUND="false"
EVAL_SYSTOLIC="null"
EVAL_DIASTOLIC="null"
EVAL_HR="null"
EVAL_TEMP="null"
EVAL_COMPLAINT="null"

if [ -n "$PATIENT_ID" ]; then
    EVAL_RECORD=$(gnuhealth_db_query "
        SELECT id,
               COALESCE(systolic::text,'null'),
               COALESCE(diastolic::text,'null'),
               COALESCE(bpm::text,'null'),
               COALESCE(temperature::text,'null')
        FROM gnuhealth_patient_evaluation
        WHERE patient = $PATIENT_ID
          AND id > $BL_EVAL
        ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

    if [ -n "$EVAL_RECORD" ]; then
        EVAL_FOUND="true"
        EVAL_SYSTOLIC=$(echo "$EVAL_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
        EVAL_DIASTOLIC=$(echo "$EVAL_RECORD" | awk -F'|' '{print $3}' | tr -d ' ')
        EVAL_HR=$(echo "$EVAL_RECORD" | awk -F'|' '{print $4}' | tr -d ' ')
        EVAL_TEMP=$(echo "$EVAL_RECORD" | awk -F'|' '{print $5}' | tr -d ' ')
    fi

    # Try to get chief complaint (column may not exist or be named differently)
    EVAL_COMPLAINT=$(gnuhealth_db_query "
        SELECT COALESCE(chief_complaint, notes, '')
        FROM gnuhealth_patient_evaluation
        WHERE patient = $PATIENT_ID AND id > $BL_EVAL
        ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)
fi
echo "Evaluation: found=$EVAL_FOUND systolic=$EVAL_SYSTOLIC diastolic=$EVAL_DIASTOLIC hr=$EVAL_HR temp=$EVAL_TEMP"

# ────────────────────────────────────────────────────────
# CHECK 7: Lab Orders (BLL_PANEL, CBC, CMP)
# ────────────────────────────────────────────────────────
LAB_ORDER_COUNT="0"
LAB_ORDER_TYPES="none"
BLL_PANEL_ORDERED="false"

if [ -n "$PATIENT_ID" ]; then
    LAB_ORDER_COUNT=$(gnuhealth_db_query "
        SELECT COUNT(*) FROM gnuhealth_patient_lab_test
        WHERE patient_id = $PATIENT_ID AND id > $BL_LAB" | tr -d '[:space:]')

    LAB_ORDER_TYPES=$(gnuhealth_db_query "
        SELECT ltt.code
        FROM gnuhealth_patient_lab_test glt
        JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id
        WHERE glt.patient_id = $PATIENT_ID AND glt.id > $BL_LAB
        ORDER BY glt.id" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

    if echo ",$LAB_ORDER_TYPES," | grep -qi ",BLL_PANEL,"; then
        BLL_PANEL_ORDERED="true"
    fi
fi
echo "Lab orders: count=$LAB_ORDER_COUNT types=$LAB_ORDER_TYPES bll_ordered=$BLL_PANEL_ORDERED"

# ────────────────────────────────────────────────────────
# CHECK 8: Prescriptions (Succimer/DMSA, Ferrous Sulfate)
# ────────────────────────────────────────────────────────
RX_COUNT="0"
RX_DRUG_NAMES="none"
HAS_SUCCIMER="false"
HAS_FERROUS="false"

if [ -n "$PATIENT_ID" ]; then
    RX_DRUG_NAMES=$(gnuhealth_db_query "
        SELECT pt.name
        FROM gnuhealth_prescription_order po
        JOIN gnuhealth_prescription_line pol ON pol.presc_order = po.id
        JOIN gnuhealth_medicament med ON pol.medicament = med.id
        JOIN product_product pp ON med.product = pp.id
        JOIN product_template pt ON pp.template = pt.id
        WHERE po.patient = $PATIENT_ID
          AND po.id > $BL_PRESC
        ORDER BY po.id" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

    RX_COUNT=$(gnuhealth_db_query "
        SELECT COUNT(DISTINCT po.id)
        FROM gnuhealth_prescription_order po
        WHERE po.patient = $PATIENT_ID AND po.id > $BL_PRESC" | tr -d '[:space:]')

    if echo "$RX_DRUG_NAMES" | grep -qi "succimer\|dmsa"; then HAS_SUCCIMER="true"; fi
    if echo "$RX_DRUG_NAMES" | grep -qi "ferrous"; then HAS_FERROUS="true"; fi
fi
echo "Prescriptions: count=$RX_COUNT drugs=$RX_DRUG_NAMES succimer=$HAS_SUCCIMER ferrous=$HAS_FERROUS"

# ────────────────────────────────────────────────────────
# CHECK 9: Follow-up Appointment
# ────────────────────────────────────────────────────────
APPT_FOUND="false"
APPT_DAYS_OUT="null"
ANY_NEW_APPTS="0"

if [ -n "$PATIENT_ID" ]; then
    APPT_RECORD=$(gnuhealth_db_query "
        SELECT id, (appointment_date::date - CURRENT_DATE::date) AS days_out
        FROM gnuhealth_appointment
        WHERE patient = $PATIENT_ID
          AND id > $BL_APPT
        ORDER BY id DESC LIMIT 1" 2>/dev/null | head -1)

    if [ -n "$APPT_RECORD" ]; then
        APPT_FOUND="true"
        APPT_DAYS_OUT=$(echo "$APPT_RECORD" | awk -F'|' '{print $2}' | tr -d ' ')
    fi

    ANY_NEW_APPTS=$(gnuhealth_db_query "
        SELECT COUNT(*) FROM gnuhealth_appointment
        WHERE patient = $PATIENT_ID AND id > $BL_APPT" | tr -d '[:space:]')
fi
echo "Appointment: found=$APPT_FOUND days_out=$APPT_DAYS_OUT any_new=${ANY_NEW_APPTS:-0}"

# ────────────────────────────────────────────────────────
# BUILD RESULT JSON
# ────────────────────────────────────────────────────────
RESULT_JSON="{
  \"task\": \"occupational_lead_exposure_full_intake\",
  \"target_patient_found\": $PATIENT_FOUND,
  \"target_patient_id\": \"${PATIENT_ID:-0}\",
  \"task_start_date\": \"$TASK_START_DATE\",

  \"lab_type_found\": $LAB_TYPE_FOUND,
  \"lab_type_name\": \"$(json_escape "$LAB_TYPE_NAME")\",
  \"lab_type_active\": $LAB_TYPE_ACTIVE,
  \"criteria_count\": ${CRITERIA_COUNT:-0},
  \"criteria_names\": \"$(json_escape "$CRITERIA_NAMES")\",

  \"disease_count\": ${DISEASE_COUNT:-0},
  \"disease_codes\": \"$(json_escape "$DISEASE_CODES")\",
  \"has_t56\": $HAS_T56,
  \"has_d64\": $HAS_D64,
  \"has_i10\": $HAS_I10,

  \"allergy_found\": $ALLERGY_FOUND,
  \"allergy_allergen\": \"$(json_escape "$ALLERGY_ALLERGEN")\",
  \"allergy_severity\": \"$(json_escape "$ALLERGY_SEVERITY")\",
  \"any_new_allergy\": ${ANY_ALLERGY:-0},

  \"family_count\": ${FAMILY_COUNT:-0},
  \"has_father\": $HAS_FATHER,
  \"has_mother\": $HAS_MOTHER,
  \"has_family_i25\": $HAS_I25,
  \"has_family_e11\": $HAS_E11,

  \"eval_found\": $EVAL_FOUND,
  \"eval_systolic\": \"$EVAL_SYSTOLIC\",
  \"eval_diastolic\": \"$EVAL_DIASTOLIC\",
  \"eval_heart_rate\": \"$EVAL_HR\",
  \"eval_temperature\": \"$EVAL_TEMP\",
  \"eval_complaint\": \"$(json_escape "$EVAL_COMPLAINT")\",

  \"lab_order_count\": ${LAB_ORDER_COUNT:-0},
  \"lab_order_types\": \"$(json_escape "$LAB_ORDER_TYPES")\",
  \"bll_panel_ordered\": $BLL_PANEL_ORDERED,

  \"rx_count\": ${RX_COUNT:-0},
  \"rx_drug_names\": \"$(json_escape "$RX_DRUG_NAMES")\",
  \"has_succimer\": $HAS_SUCCIMER,
  \"has_ferrous\": $HAS_FERROUS,

  \"appointment_found\": $APPT_FOUND,
  \"appointment_days_out\": \"$APPT_DAYS_OUT\",
  \"any_new_appointments\": ${ANY_NEW_APPTS:-0},

  \"screenshot_exists\": $([ -f /tmp/${PREFIX}_final_state.png ] && echo "true" || echo "false")
}"

safe_write_result "/tmp/occupational_lead_exposure_full_intake_result.json" "$RESULT_JSON"
echo "Result saved to /tmp/occupational_lead_exposure_full_intake_result.json"
echo "=== Export Complete ==="
