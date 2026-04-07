#!/bin/bash
echo "=== Setting up occupational_asthma_management task ==="

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
echo "$JOHN_PATIENT_ID" > /tmp/asthma_target_patient_id
chmod 666 /tmp/asthma_target_patient_id 2>/dev/null || true

# --- 2. Ensure lab test types exist ---
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

echo "Ensuring IgE lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'TOTAL IGE', 'IGE', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'IGE' OR UPPER(name) LIKE '%IGE%'
    );
" 2>/dev/null || true

# --- 3. Contamination injection: J45 asthma on Luna ---
echo "Injecting contamination: J45 Asthma diagnosis on Luna..."
LUNA_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Luna%'
    LIMIT 1" | tr -d '[:space:]')

if [ -n "$LUNA_PATIENT_ID" ]; then
    J45_PATHOLOGY_ID=$(gnuhealth_db_query "
        SELECT id FROM gnuhealth_pathology WHERE code = 'J45' LIMIT 1" | tr -d '[:space:]')
    if [ -n "$J45_PATHOLOGY_ID" ]; then
        EXISTING=$(gnuhealth_db_query "
            SELECT COUNT(*) FROM gnuhealth_patient_disease
            WHERE patient = $LUNA_PATIENT_ID AND pathology = $J45_PATHOLOGY_ID" | tr -d '[:space:]')
        if [ "${EXISTING:-0}" -eq 0 ]; then
            gnuhealth_db_query "
                INSERT INTO gnuhealth_patient_disease (id, patient, pathology, is_active, create_uid, create_date, write_uid, write_date)
                VALUES (
                    (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_patient_disease),
                    $LUNA_PATIENT_ID, $J45_PATHOLOGY_ID, true, 1, NOW(), 1, NOW()
                )
            " 2>/dev/null || true
        fi
    fi
fi

# --- 4. Clean pre-existing asthma records and today's evaluations for John ---
echo "Cleaning pre-existing J45 records for John Zenon..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $JOHN_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'J45%')
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

echo "$BASELINE_DISEASE_MAX" > /tmp/asthma_baseline_disease_max
echo "$BASELINE_EVAL_MAX" > /tmp/asthma_baseline_eval_max
echo "$BASELINE_PRESCRIPTION_MAX" > /tmp/asthma_baseline_prescription_max
echo "$BASELINE_LAB_MAX" > /tmp/asthma_baseline_lab_max
echo "$BASELINE_APPT_MAX" > /tmp/asthma_baseline_appt_max
for f in /tmp/asthma_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/asthma_task_start_date
chmod 666 /tmp/asthma_task_start_date 2>/dev/null || true

# Take initial screenshot and print instructions
ensure_firefox_gnuhealth

sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Patient: John Zenon"
echo "Baselines recorded. Agent can now begin task execution."