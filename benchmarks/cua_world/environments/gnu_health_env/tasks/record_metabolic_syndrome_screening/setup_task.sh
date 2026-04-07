#!/bin/bash
echo "=== Setting up record_metabolic_syndrome_screening task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find Bonifacio Caput ---
BONIFACIO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Bonifacio%' AND pp.lastname ILIKE '%Caput%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$BONIFACIO_PATIENT_ID" ]; then
    echo "FATAL: Patient Bonifacio Caput not found in demo database. Aborting."
    exit 1
fi
echo "Bonifacio Caput patient_id: $BONIFACIO_PATIENT_ID"
echo "$BONIFACIO_PATIENT_ID" > /tmp/metabolic_target_patient_id
chmod 666 /tmp/metabolic_target_patient_id 2>/dev/null || true

# --- 2. Ensure lab test types exist ---
echo "Ensuring FASTING GLUCOSE lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'FASTING BLOOD GLUCOSE', 'FBG', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'FBG' OR UPPER(name) LIKE '%GLUCOSE%'
    );
" 2>/dev/null || true

echo "Ensuring LIPID PANEL lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'LIPID PANEL', 'LIPID', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'LIPID' OR UPPER(name) LIKE '%LIPID%'
    );
" 2>/dev/null || true

# --- 3. Contamination injection: I10 on Ana Betz (wrong patient) ---
echo "Injecting contamination: I10 Hypertension on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    I10_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code = 'I10' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$I10_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $I10_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $I10_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing disease records (E11, I10, E78) for Bonifacio ---
echo "Cleaning pre-existing metabolic disease records for Bonifacio..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $BONIFACIO_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'E11%' OR code LIKE 'E14%' OR code LIKE 'I10%' OR code LIKE 'E78%')
" 2>/dev/null || true

echo "Cleaning pre-existing lifestyle records for Bonifacio..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_lifestyle
    WHERE patient_lifestyle = $BONIFACIO_PATIENT_ID
       OR patient = $BONIFACIO_PATIENT_ID
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_LIFESTYLE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lifestyle" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline prescription max: $BASELINE_PRESCRIPTION_MAX"
echo "Baseline lab max: $BASELINE_LAB_MAX"
echo "Baseline lifestyle max: $BASELINE_LIFESTYLE_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

echo "$BASELINE_DISEASE_MAX" > /tmp/metabolic_baseline_disease_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/metabolic_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/metabolic_baseline_lab_max
echo "$BASELINE_LIFESTYLE_MAX" > /tmp/metabolic_baseline_lifestyle_max
echo "$BASELINE_APPT_MAX" > /tmp/metabolic_baseline_appt_max
for f in /tmp/metabolic_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/metabolic_task_start_date
chmod 666 /tmp/metabolic_task_start_date 2>/dev/null || true

# --- 6. Ensure GNU Health is running ---
ensure_firefox_gnuhealth
ensure_gnuhealth_logged_in "http://localhost:8000/#menu_id=105&action_id=125"

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="