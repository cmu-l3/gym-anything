#!/bin/bash
echo "=== Setting up occupational_hypersensitivity_pneumonitis task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find John Zenon ---
JOHN_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%John%' AND pp.lastname ILIKE '%Zenon%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$JOHN_PATIENT_ID" ]; then
    echo "FATAL: Patient John Zenon not found in demo database. Aborting."
    exit 1
fi
echo "John Zenon patient_id: $JOHN_PATIENT_ID"
echo "$JOHN_PATIENT_ID" > /tmp/ohp_target_patient_id
chmod 666 /tmp/ohp_target_patient_id 2>/dev/null || true

# Get party_id for logging
JOHN_PARTY_ID=$(gnuhealth_db_query "
    SELECT gp.party FROM gnuhealth_patient gp WHERE gp.id = $JOHN_PATIENT_ID LIMIT 1" | tr -d '[:space:]')
echo "$JOHN_PARTY_ID" > /tmp/ohp_target_party_id
chmod 666 /tmp/ohp_target_party_id 2>/dev/null || true

# --- 2. Ensure required lab/diagnostic test types exist ---
echo "Ensuring CHEST X-RAY diagnostic test exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT 
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'CHEST X-RAY (CXR)', 'CXR', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CXR' OR UPPER(name) LIKE '%CHEST X-RAY%'
    );
" 2>/dev/null || true

echo "Ensuring SERUM IGE lab test exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT 
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'TOTAL SERUM IGE', 'IGE', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'IGE' OR UPPER(name) LIKE '%IGE%'
    );
" 2>/dev/null || true

echo "Ensuring CBC lab test exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT 
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'COMPLETE BLOOD COUNT', 'CBC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CBC' OR UPPER(name) LIKE '%COMPLETE BLOOD COUNT%'
    );
" 2>/dev/null || true

# --- 3. Contamination: J67 Hypersensitivity Pneumonitis on Ana Betz (wrong patient) ---
echo "Injecting contamination: J67 diagnosis on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    J67_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'J67%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$J67_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease 
            WHERE patient = $ANA_PATIENT_ID AND pathology = $J67_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $J67_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing J67 records and today's evaluations for John ---
echo "Cleaning pre-existing J67 records for John..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'J67%')
" 2>/dev/null || true

echo "Cleaning pre-existing evaluations for John from today..."
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $JOHN_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/ohp_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/ohp_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/ohp_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/ohp_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/ohp_baseline_appt_max
for f in /tmp/ohp_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/ohp_task_start_date
date +%s > /tmp/ohp_task_start_timestamp
chmod 666 /tmp/ohp_task_start_date /tmp/ohp_task_start_timestamp 2>/dev/null || true

# --- 6. Launch Firefox ---
ensure_firefox_gnuhealth
take_screenshot /tmp/ohp_initial_state.png

echo "=== Setup complete ==="