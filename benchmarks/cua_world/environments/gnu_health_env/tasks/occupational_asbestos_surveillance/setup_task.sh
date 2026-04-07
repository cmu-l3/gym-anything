#!/bin/bash
echo "=== Setting up occupational_asbestos_surveillance task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find target patient (Roberto Carlos) ---
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$ROBERTO_PATIENT_ID" ]; then
    echo "FATAL: Patient Roberto Carlos not found in demo database. Aborting."
    exit 1
fi
echo "Roberto Carlos patient_id: $ROBERTO_PATIENT_ID"
echo "$ROBERTO_PATIENT_ID" > /tmp/oas_target_patient_id
chmod 666 /tmp/oas_target_patient_id 2>/dev/null || true

# --- 2. Ensure cardiopulmonary lab test types exist ---
echo "Ensuring CBC lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'COMPLETE BLOOD COUNT', 'CBC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CBC' OR UPPER(name) LIKE '%COMPLETE BLOOD COUNT%'
    );
" 2>/dev/null || true

echo "Ensuring ARTERIAL BLOOD GAS lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'ARTERIAL BLOOD GAS', 'ABG', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'ABG' OR UPPER(name) LIKE '%ARTERIAL BLOOD GAS%'
    );
" 2>/dev/null || true

# --- 3. Contamination: Asbestos diagnosis on wrong patient (Ana Betz) ---
echo "Injecting contamination: J92 Pleural Plaque on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    J92_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code = 'J92' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$J92_PATHOLOGY_ID" ]; then
        EXISTING_CONTAM=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ANA_PATIENT_ID AND pathology = $J92_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING_CONTAM:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ANA_PATIENT_ID, $J92_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing task-specific records for Roberto ---
echo "Cleaning pre-existing J92/J61 diagnosis records for Roberto..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $ROBERTO_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'J92%' OR code LIKE 'J61%')
" 2>/dev/null || true

echo "Cleaning pre-existing lifestyle records for Roberto..."
# Tryton often uses "name" as the FK in lifestyle, sometimes "patient". Try both:
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_lifestyle
    WHERE name = $ROBERTO_PATIENT_ID OR patient = $ROBERTO_PATIENT_ID
" 2>/dev/null || true

echo "Cleaning evaluations/appointments from today onwards for Roberto..."
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation WHERE patient = $ROBERTO_PATIENT_ID AND create_date::date >= '$TODAY';
    DELETE FROM gnuhealth_appointment WHERE patient = $ROBERTO_PATIENT_ID AND appointment_date::date >= '$TODAY';
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_LIFESTYLE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lifestyle" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/oas_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/oas_baseline_eval_max
echo "$BASELINE_LAB_MAX" > /tmp/oas_baseline_lab_max
echo "$BASELINE_LIFESTYLE_MAX" > /tmp/oas_baseline_lifestyle_max
echo "$BASELINE_APPT_MAX" > /tmp/oas_baseline_appt_max
date +%Y-%m-%d > /tmp/oas_task_start_date

chmod 666 /tmp/oas_baseline_* /tmp/oas_task_start_date 2>/dev/null || true

# --- 6. Ensure GNU Health is running and logged in ---
ensure_gnuhealth_logged_in "http://localhost:8000/#menu"
sleep 2
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task setup complete ==="