#!/bin/bash
echo "=== Setting up occupational_berylliosis_surveillance task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find target patient John Zenon ---
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
echo "$JOHN_PATIENT_ID" > /tmp/beryl_target_patient_id
chmod 666 /tmp/beryl_target_patient_id 2>/dev/null || true

# --- 2. Ensure lab test types exist ---
echo "Ensuring required lab test types exist..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'IMMUNOLOGY PANEL', 'IMMUNO', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'IMMUNO' OR UPPER(name) LIKE '%IMMUNOLOGY%');
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'COMPLETE BLOOD COUNT', 'CBC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CBC' OR UPPER(name) LIKE '%COMPLETE BLOOD COUNT%');
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'BASIC METABOLIC PANEL', 'BMP', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'BMP' OR UPPER(name) LIKE '%BASIC METABOLIC%');
" 2>/dev/null || true

# --- 3. Contamination: J63.2 Berylliosis diagnosis on Roberto Carlos (distractor) ---
echo "Injecting contamination: J63.2 Berylliosis on Roberto Carlos..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    J632_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code = 'J63.2' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$J632_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ROBERTO_PATIENT_ID AND pathology = $J632_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES ((SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease), $ROBERTO_PATIENT_ID, $J632_PATHOLOGY_ID, true, 1, NOW(), 1, NOW())
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing J63.x records for John Zenon ---
echo "Cleaning pre-existing J63 records for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'J63%')
" 2>/dev/null || true

echo "Cleaning pre-existing evaluations for John Zenon from today..."
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

echo "$BASELINE_DISEASE_MAX" > /tmp/beryl_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/beryl_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/beryl_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/beryl_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/beryl_baseline_appt_max
for f in /tmp/beryl_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/beryl_task_start_date
chmod 666 /tmp/beryl_task_start_date 2>/dev/null || true
date +%s > /tmp/task_start_time.txt

# --- 6. Ensure GNU Health is running ---
ensure_gnuhealth_logged_in "http://localhost:8000/#health50/model/gnuhealth.patient"
sleep 2

take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="