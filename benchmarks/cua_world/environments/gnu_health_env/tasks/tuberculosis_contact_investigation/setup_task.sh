#!/bin/bash
echo "=== Setting up tuberculosis_contact_investigation task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find Matt Zenon Betz ---
MATT_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Matt%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$MATT_PATIENT_ID" ]; then
    MATT_PATIENT_ID=$(gnuhealth_db_query "
        SELECT gp.id
        FROM gnuhealth_patient gp
        JOIN party_party pp ON gp.party = pp.id
        WHERE CONCAT(pp.name, ' ', COALESCE(pp.lastname,'')) ILIKE '%Matt%Betz%'
        LIMIT 1" | tr -d '[:space:]')
fi

if [ -z "$MATT_PATIENT_ID" ]; then
    echo "FATAL: Patient Matt Zenon Betz not found in demo database. Aborting."
    exit 1
fi
echo "Matt Zenon Betz patient_id: $MATT_PATIENT_ID"
echo "$MATT_PATIENT_ID" > /tmp/tb_target_patient_id
chmod 666 /tmp/tb_target_patient_id 2>/dev/null || true

# --- 2. Ensure AFB/sputum lab test types exist ---
echo "Ensuring AFB CULTURE lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'AFB CULTURE (SPUTUM)', 'AFB_CULTURE', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'AFB_CULTURE' OR UPPER(name) LIKE '%AFB%CULTURE%'
    );
" 2>/dev/null || true

echo "Ensuring AFB SMEAR lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'AFB SMEAR (SPUTUM)', 'AFB_SMEAR', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'AFB_SMEAR' OR UPPER(name) LIKE '%AFB%SMEAR%'
    );
" 2>/dev/null || true

echo "Ensuring SPUTUM CULTURE lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'SPUTUM CULTURE', 'SPUTUM', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'SPUTUM' OR UPPER(name) LIKE '%SPUTUM%CULTURE%'
    );
" 2>/dev/null || true

# --- 3. Contamination: J06 URI diagnosis on Bonifacio Caput ---
echo "Injecting contamination: J06 URI on Bonifacio Caput..."
BONIFACIO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Bonifacio%' AND pp.lastname ILIKE '%Caput%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$BONIFACIO_PATIENT_ID" ]; then
    J06_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code = 'J06' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$J06_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $BONIFACIO_PATIENT_ID AND pathology = $J06_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $BONIFACIO_PATIENT_ID, $J06_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing A15 TB records and family disease records for Matt ---
echo "Cleaning pre-existing A15 TB records for Matt..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $MATT_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'A15%')
" 2>/dev/null || true

echo "Cleaning pre-existing family disease records for Matt..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_family_diseases
    WHERE patient = $MATT_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'A15%' OR code LIKE 'A16%' OR code LIKE 'Z20%')
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_FAMILY_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_family_diseases" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline prescription max: $BASELINE_PRESCRIPTION_MAX"
echo "Baseline lab max: $BASELINE_LAB_MAX"
echo "Baseline family disease max: $BASELINE_FAMILY_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

echo "$BASELINE_DISEASE_MAX" > /tmp/tb_baseline_disease_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/tb_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/tb_baseline_lab_max
echo "$BASELINE_FAMILY_MAX" > /tmp/tb_baseline_family_max
echo "$BASELINE_APPT_MAX" > /tmp/tb_baseline_appt_max
for f in /tmp/tb_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/tb_task_start_date
chmod 666 /tmp/tb_task_start_date 2>/dev/null || true

# --- 6. Ensure GNU Health is running ---
if ! curl -s --max-time 5 http://localhost:8000/ > /dev/null 2>&1; then
    echo "Starting GNU Health server..."
    systemctl start gnuhealth
    sleep 15
fi

ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5
take_screenshot /tmp/tb_initial_state.png

echo "=== tuberculosis_contact_investigation setup complete ==="
echo "Target patient: Matt Zenon Betz (patient_id=$MATT_PATIENT_ID)"
echo "Clinical scenario: Active pulmonary TB — RIPE regimen + contact investigation"
echo "IMPORTANT: This is a very_hard task — the agent must independently determine:"
echo "  - Correct ICD-10 code for pulmonary TB (A15.x)"
echo "  - Standard RIPE regimen drugs (Rifampin, Isoniazid, Pyrazinamide, Ethambutol)"
echo "  - Appropriate microbiological lab orders (AFB culture, sputum)"
echo "  - Contact investigation documentation via family disease history"
echo "  - Treatment response evaluation timing (10-21 days)"
