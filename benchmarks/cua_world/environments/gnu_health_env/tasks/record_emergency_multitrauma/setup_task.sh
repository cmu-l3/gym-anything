#!/bin/bash
echo "=== Setting up record_emergency_multitrauma task ==="

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
echo "$MATT_PATIENT_ID" > /tmp/trauma_target_patient_id
chmod 666 /tmp/trauma_target_patient_id 2>/dev/null || true

# --- 2. Ensure required lab test types exist (CBC, PT/INR, CMP) ---
echo "Ensuring required trauma lab test types exist..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'COMPLETE BLOOD COUNT', 'CBC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CBC' OR UPPER(name) LIKE '%COMPLETE BLOOD COUNT%'
    );
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'PROTHROMBIN TIME / INR', 'PT_INR', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'PT_INR' OR UPPER(name) LIKE '%PROTHROMBIN%' OR UPPER(name) LIKE '%PT/INR%'
    );
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'COMPREHENSIVE METABOLIC PANEL', 'CMP', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CMP' OR UPPER(name) LIKE '%COMPREHENSIVE METABOLIC%'
    );
" 2>/dev/null || true

# --- 3. Contamination: S-code fracture on Ana Betz (wrong patient) ---
echo "Injecting contamination: S82 fracture on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    S82_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'S82%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$S82_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $S82_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $S82_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing S-codes and evaluations for Matt ---
echo "Cleaning pre-existing S-code disease records for Matt..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $MATT_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'S%')
" 2>/dev/null || true

echo "Cleaning pre-existing evaluations for Matt from today..."
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $MATT_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline eval max: $BASELINE_EVAL_MAX"
echo "Baseline prescription max: $BASELINE_PRESCRIPTION_MAX"
echo "Baseline lab max: $BASELINE_LAB_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

echo "$BASELINE_DISEASE_MAX" > /tmp/trauma_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/trauma_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/trauma_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/trauma_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/trauma_baseline_appt_max
for f in /tmp/trauma_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/trauma_task_start_date
chmod 666 /tmp/trauma_task_start_date 2>/dev/null || true

# --- 6. Take initial screenshot and launch GNU Health ---
take_screenshot /tmp/trauma_initial_state.png

echo "Starting Firefox and logging in to GNU Health..."
su - ga -c "DISPLAY=:1 firefox http://localhost:8000/ &"
sleep 5
ensure_gnuhealth_logged_in

echo "=== Task setup complete ==="