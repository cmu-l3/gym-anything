#!/bin/bash
echo "=== Setting up occupational_respirator_medical_clearance task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find target patient: John Zenon ---
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
echo "$JOHN_PATIENT_ID" > /tmp/resp_target_patient_id
chmod 666 /tmp/resp_target_patient_id 2>/dev/null || true

# --- 2. Ensure required Imaging and Lab test types exist ---
echo "Ensuring CHEST X-RAY imaging test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_imaging_test (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_imaging_test),
        'CHEST X-RAY PA/LAT', 'CXR', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_imaging_test WHERE code = 'CXR' OR UPPER(name) LIKE '%CHEST X-RAY%'
    );
" 2>/dev/null || true

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

# --- 3. Contamination: Z02.1 Encounter for pre-employment examination on Roberto Carlos ---
echo "Injecting contamination: Z02.1 on Roberto Carlos..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    Z02_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'Z02%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$Z02_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ROBERTO_PATIENT_ID AND pathology = $Z02_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ROBERTO_PATIENT_ID, $Z02_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing Z-code records and evaluations for John Zenon ---
echo "Cleaning pre-existing Z-code disease records for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'Z%')
" 2>/dev/null || true

echo "Cleaning pre-existing evaluations for John Zenon from today..."
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $JOHN_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record baselines for anti-gaming ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_IMAGING_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_imaging_test_request" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline eval max: $BASELINE_EVAL_MAX"
echo "Baseline imaging max: $BASELINE_IMAGING_MAX"
echo "Baseline lab max: $BASELINE_LAB_MAX"
echo "Baseline appt max: $BASELINE_APPT_MAX"

echo "$BASELINE_DISEASE_MAX" > /tmp/resp_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/resp_baseline_eval_max
echo "$BASELINE_IMAGING_MAX" > /tmp/resp_baseline_imaging_max
echo "$BASELINE_LAB_MAX" > /tmp/resp_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/resp_baseline_appt_max
for f in /tmp/resp_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

# Save task start metadata
date +%s > /tmp/task_start_time.txt
date +%Y-%m-%d > /tmp/resp_task_start_date
chmod 666 /tmp/task_start_time.txt /tmp/resp_task_start_date 2>/dev/null || true

# --- 6. Configure UI ---
echo "Configuring Firefox and starting GNU Health..."
ensure_gnuhealth_logged_in "http://localhost:8000/#menu"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="