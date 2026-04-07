#!/bin/bash
echo "=== Setting up occupational_legionellosis_response task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# Record task start time
date +%s > /tmp/task_start_time.txt
date +%Y-%m-%d > /tmp/legion_task_start_date
chmod 666 /tmp/legion_task_start_date 2>/dev/null || true

# --- 1. Find John Zenon ---
JOHN_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%John%' AND pp.lastname ILIKE '%Zenon%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$JOHN_PATIENT_ID" ]; then
    JOHN_PATIENT_ID=$(gnuhealth_db_query "
        SELECT gp.id
        FROM gnuhealth_patient gp
        JOIN party_party pp ON gp.party = pp.id
        WHERE CONCAT(COALESCE(pp.name,''), ' ', COALESCE(pp.lastname,'')) ILIKE '%John%Zenon%'
        LIMIT 1" | tr -d '[:space:]')
fi

if [ -z "$JOHN_PATIENT_ID" ]; then
    echo "FATAL: Patient 'John Zenon' not found in demo database. Aborting."
    exit 1
fi
echo "John Zenon patient_id: $JOHN_PATIENT_ID"
echo "$JOHN_PATIENT_ID" > /tmp/legion_target_patient_id
chmod 666 /tmp/legion_target_patient_id 2>/dev/null || true

# --- 2. Ensure standard lab test types exist ---
echo "Ensuring required lab test types exist..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'URINALYSIS', 'UA', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'UA' OR UPPER(name) LIKE '%URINALYSIS%');
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

# --- 3. Contamination injection: A48.1 diagnosis on Ana Betz ---
echo "Injecting contamination: Legionnaires' diagnosis on Ana Betz..."
ANA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ANA_PATIENT_ID" ]; then
    A48_PATHOLOGY_ID=$(gnuhealth_db_query "SELECT id FROM gnuhealth_pathology WHERE code = 'A48.1' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$A48_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient_disease WHERE patient = $ANA_PATIENT_ID AND pathology = $A48_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES ((SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease), $ANA_PATIENT_ID, $A48_PATHOLOGY_ID, true, 1, NOW(), 1, NOW())
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing A48/Legionnaires records for John ---
echo "Cleaning pre-existing A48.1 records for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'A48%')
" 2>/dev/null || true

# Clean evaluations from today
TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $JOHN_PATIENT_ID AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/legion_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/legion_baseline_eval_max
echo "$BASELINE_LAB_MAX" > /tmp/legion_baseline_lab_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/legion_baseline_prescription_max
echo "$BASELINE_APPT_MAX" > /tmp/legion_baseline_appt_max
for f in /tmp/legion_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

# --- 6. Ensure UI is ready ---
ensure_firefox_gnuhealth
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="