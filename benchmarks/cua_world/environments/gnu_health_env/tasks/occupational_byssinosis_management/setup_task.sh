#!/bin/bash
echo "=== Setting up occupational_byssinosis_management task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find Ana Isabel Betz ---
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$ANA_PATIENT_ID" ]; then
    echo "FATAL: Patient Ana Isabel Betz not found in demo database. Aborting."
    exit 1
fi
echo "Ana Isabel Betz patient_id: $ANA_PATIENT_ID"
echo "$ANA_PATIENT_ID" > /tmp/byss_target_patient_id
chmod 666 /tmp/byss_target_patient_id 2>/dev/null || true

# --- 2. Ensure required lab/diagnostic test types exist ---
echo "Ensuring SPIROMETRY lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'SPIROMETRY', 'SPIRO', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'SPIRO' OR UPPER(name) LIKE '%SPIROMETRY%'
    );
" 2>/dev/null || true

echo "Ensuring CHEST X-RAY test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'CHEST X-RAY', 'CXR', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CXR' OR UPPER(name) LIKE '%CHEST X-RAY%'
    );
" 2>/dev/null || true

echo "Ensuring ARTERIAL BLOOD GAS test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'ARTERIAL BLOOD GAS', 'ABG', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'ABG' OR UPPER(name) LIKE '%ARTERIAL BLOOD GAS%'
    );
" 2>/dev/null || true

# --- 3. Contamination: J66 Byssinosis diagnosis on Roberto Carlos (wrong patient) ---
echo "Injecting contamination: J66 on Roberto Carlos..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    J66_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'J66%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$J66_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ROBERTO_PATIENT_ID AND pathology = $J66_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ROBERTO_PATIENT_ID, $J66_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing J66 records and recent evaluations for Ana ---
echo "Cleaning pre-existing J66 records for Ana..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $ANA_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'J66%')
" 2>/dev/null || true

echo "Cleaning pre-existing evaluations for Ana from today..."
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $ANA_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record baselines for Anti-Gaming ---
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

echo "$BASELINE_DISEASE_MAX" > /tmp/byss_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/byss_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/byss_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/byss_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/byss_baseline_appt_max
for f in /tmp/byss_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

# Record task start timestamp and date
date +%s > /tmp/task_start_time.txt
date +%Y-%m-%d > /tmp/byss_task_start_date
chmod 666 /tmp/task_start_time.txt /tmp/byss_task_start_date 2>/dev/null || true

# --- 6. Ensure GNU Health is running in Firefox ---
ensure_firefox_gnuhealth
sleep 2

# Take initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="