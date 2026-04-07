#!/bin/bash
echo "=== Setting up record_occupational_disease task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/occ_task_start_time.txt

# Wait for database to be ready
wait_for_postgres

# --- 1. Find John Zenon ---
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
echo "$TARGET_PATIENT_ID" > /tmp/occ_target_patient_id
chmod 666 /tmp/occ_target_patient_id 2>/dev/null || true

# --- 2. Ensure Pathology code H83.3 exists ---
echo "Ensuring ICD-10 code H83.3 exists in database..."
gnuhealth_db_query "
    INSERT INTO gnuhealth_pathology (id, code, name, active, create_uid, create_date, write_uid, write_date)
    SELECT
        (SELECT COALESCE(MAX(id), 0) + 1 FROM gnuhealth_pathology),
        'H83.3', 'Noise effects on inner ear', true, 1, NOW(), 1, NOW()
    WHERE NOT EXISTS (
        SELECT 1 FROM gnuhealth_pathology WHERE code = 'H83.3'
    );
" 2>/dev/null || true

# --- 3. Clean pre-existing H83.3 disease records for John Zenon ---
echo "Cleaning any existing H83.3 records for John Zenon to ensure clean state..."
gnuhealth_db_query "
    DELETE FROM gnuhealth_patient_disease
    WHERE patient = $TARGET_PATIENT_ID
      AND pathology IN (SELECT id FROM gnuhealth_pathology WHERE code = 'H83.3')
" 2>/dev/null || true

# --- 4. Record baseline disease count ---
echo "Recording baseline state..."
BASELINE_DISEASE_COUNT=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient_disease WHERE patient = $TARGET_PATIENT_ID" | tr -d '[:space:]')
BASELINE_DISEASE_MAX_ID=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_patient_disease WHERE patient = $TARGET_PATIENT_ID" | tr -d '[:space:]')

echo "Baseline diseases for John Zenon: $BASELINE_DISEASE_COUNT (Max ID: $BASELINE_DISEASE_MAX_ID)"
echo "$BASELINE_DISEASE_COUNT" > /tmp/occ_baseline_count.txt
echo "$BASELINE_DISEASE_MAX_ID" > /tmp/occ_baseline_max_id.txt
chmod 666 /tmp/occ_baseline_count.txt /tmp/occ_baseline_max_id.txt 2>/dev/null || true

# --- 5. Start Firefox and login ---
echo "Starting Firefox and ensuring login..."
ensure_gnuhealth_logged_in "http://localhost:8000/#menu"

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial_state.png ga

echo "=== Setup complete ==="