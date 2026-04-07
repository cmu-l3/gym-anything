#!/bin/bash
echo "=== Setting up occupational_co_toxicity_protocol task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find Target Patient: John Zenon ---
TARGET_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%John%' AND pp.lastname ILIKE '%Zenon%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$TARGET_PATIENT_ID" ]; then
    echo "FATAL: Patient John Zenon not found in demo database. Aborting."
    exit 1
fi
echo "John Zenon patient_id: $TARGET_PATIENT_ID"
echo "$TARGET_PATIENT_ID" > /tmp/co_target_patient_id
chmod 666 /tmp/co_target_patient_id 2>/dev/null || true

# --- 2. Ensure basic lab test types exist ---
echo "Ensuring CBC and CMP lab test types exist..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'COMPLETE BLOOD COUNT', 'CBC', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CBC');
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'BASIC METABOLIC PANEL', 'BMP', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'BMP');
" 2>/dev/null || true

gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type), 'ARTERIAL BLOOD GAS', 'ABG', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'ABG');
" 2>/dev/null || true

# --- 3. Inject Contamination: T59 Diagnosis on Roberto Carlos ---
echo "Injecting contamination: T59.x diagnosis on Roberto Carlos..."
ROBERTO_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Roberto%' AND pp.lastname ILIKE '%Carlos%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$ROBERTO_PATIENT_ID" ]; then
    T59_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T59%' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$T59_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $ROBERTO_PATIENT_ID AND pathology = $T59_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $ROBERTO_PATIENT_ID, $T59_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean up pre-existing target records to ensure clean state ---
echo "Cleaning pre-existing T59 records and today's evaluations for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T59%')
" 2>/dev/null || true

TODAY=$(date +%Y-%m-%d)
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_evaluation
    WHERE patient = $TARGET_PATIENT_ID
      AND create_date::date >= '$TODAY'
" 2>/dev/null || true

# --- 5. Record Baselines ---
echo "Recording baseline state..."
BASELINE_DISEASE_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')
BASELINE_PRESCRIPTION_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_prescription_order" | tr -d '[:space:]')
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_APPT_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_appointment" | tr -d '[:space:]')

echo "$BASELINE_DISEASE_MAX" > /tmp/co_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/co_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/co_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/co_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/co_baseline_appt_max
echo "$TODAY" > /tmp/co_task_start_date

chmod 666 /tmp/co_baseline_* 2>/dev/null || true
chmod 666 /tmp/co_task_start_date 2>/dev/null || true

# --- 6. Launch Application ---
echo "Ensuring GNU Health Web UI is running..."
ensure_gnuhealth_logged_in "http://localhost:8000/#"
sleep 2
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="