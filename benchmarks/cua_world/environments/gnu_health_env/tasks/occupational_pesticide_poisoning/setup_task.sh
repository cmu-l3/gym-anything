#!/bin/bash
echo "=== Setting up occupational_pesticide_poisoning task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# Record task start time
date +%s > /tmp/task_start_time.txt
date +%Y-%m-%d > /tmp/pest_task_start_date
chmod 666 /tmp/task_start_time.txt /tmp/pest_task_start_date 2>/dev/null || true

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
echo "$JOHN_PATIENT_ID" > /tmp/pest_target_patient_id
chmod 666 /tmp/pest_target_patient_id 2>/dev/null || true

# --- 2. Ensure required lab test types exist ---
echo "Ensuring CHOLINESTERASE lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'CHOLINESTERASE LEVEL', 'CHOLINE', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CHOLINE' OR UPPER(name) LIKE '%CHOLINESTERASE%'
    );
" 2>/dev/null || true

echo "Ensuring CBC and CMP lab test types exist..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'COMPLETE BLOOD COUNT', 'CBC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CBC');
" 2>/dev/null || true
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'COMPREHENSIVE METABOLIC PANEL', 'CMP', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CMP');
" 2>/dev/null || true

# --- 3. Contamination injection: T60 code on Roberto Carlos ---
echo "Injecting contamination: organophosphate poisoning on Roberto Carlos..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    T60_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T60%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$T60_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ROBERTO_PATIENT_ID AND pathology = $T60_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ROBERTO_PATIENT_ID, $T60_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing T-code records and today's evaluations for John Zenon ---
echo "Cleaning pre-existing T60 records for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T60%')
" 2>/dev/null || true

TODAY=$(date +%Y-%m-%d)
echo "Cleaning today's evaluations for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $JOHN_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/pest_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/pest_baseline_eval_max
echo "$BASELINE_LAB_MAX" > /tmp/pest_baseline_lab_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/pest_baseline_prescription_max
echo "$BASELINE_APPT_MAX" > /tmp/pest_baseline_appt_max
for f in /tmp/pest_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

# --- 6. Prepare UI ---
ensure_gnuhealth_logged_in "http://localhost:8000/#menu"
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="