#!/bin/bash
echo "=== Setting up groundwater_heavy_metal_exposure task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Find John Zenon ---
JOHN_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%John%' AND (pp.lastname ILIKE '%Zenon%' OR pp.name ILIKE '%Zenon%')
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$JOHN_PATIENT_ID" ]; then
    echo "FATAL: Patient John Zenon not found in demo database. Aborting."
    exit 1
fi
echo "John Zenon patient_id: $JOHN_PATIENT_ID"
echo "$JOHN_PATIENT_ID" > /tmp/ghme_john_patient_id

# --- 2. Find Matt Zenon Betz ---
MATT_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Matt%' AND (pp.lastname ILIKE '%Betz%' OR pp.name ILIKE '%Betz%')
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$MATT_PATIENT_ID" ]; then
    echo "FATAL: Patient Matt Zenon Betz not found in demo database. Aborting."
    exit 1
fi
echo "Matt Zenon Betz patient_id: $MATT_PATIENT_ID"
echo "$MATT_PATIENT_ID" > /tmp/ghme_matt_patient_id

chmod 666 /tmp/ghme_john_patient_id /tmp/ghme_matt_patient_id 2>/dev/null || true

# --- 3. Ensure laboratory test types exist ---
echo "Ensuring TOXICOLOGY SCREEN lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'TOXICOLOGY SCREEN', 'TOX_SCREEN', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'TOX_SCREEN' OR UPPER(name) LIKE '%TOXICOLOGY%'
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

echo "Ensuring CMP lab test type exists..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_lab_test_type (id, name, code, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_lab_test_type),
        'COMPREHENSIVE METABOLIC PANEL', 'CMP', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_lab_test_type WHERE code = 'CMP' OR UPPER(name) LIKE '%COMPREHENSIVE METABOLIC%'
    );
" 2>/dev/null || true

# --- 4. Clean pre-existing task-related data ---
echo "Cleaning pre-existing T56 records for both patients..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient IN ($JOHN_PATIENT_ID, $MATT_PATIENT_ID)
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code LIKE 'T56%')
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
BASELINE_LAB_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_lab_test" | tr -d '[:space:]')
BASELINE_EVAL_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_evaluation" | tr -d '[:space:]')

echo "Baseline disease max: $BASELINE_DISEASE_MAX"
echo "Baseline lab max: $BASELINE_LAB_MAX"
echo "Baseline eval max: $BASELINE_EVAL_MAX"

echo "$BASELINE_DISEASE_MAX" > /tmp/ghme_baseline_disease_max
echo "$BASELINE_LAB_MAX" > /tmp/ghme_baseline_lab_max
echo "$BASELINE_EVAL_MAX" > /tmp/ghme_baseline_eval_max
for f in /tmp/ghme_baseline_*; do chmod 666 "$f" 2>/dev/null || true; done

date +%Y-%m-%d > /tmp/ghme_task_start_date
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/ghme_task_start_date /tmp/task_start_time.txt 2>/dev/null || true

# --- 6. Warm up UI / Firefox ---
ensure_gnuhealth_logged_in "http://localhost:8000/#menu_id=221"

sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="