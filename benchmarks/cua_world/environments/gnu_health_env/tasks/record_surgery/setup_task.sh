#!/bin/bash
echo "=== Setting up record_surgery task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
date -Iseconds > /tmp/surgery_task_start_date

# Wait for PostgreSQL
wait_for_postgres 60

# --- 1. Find target patient Ana Betz ---
TARGET_PATIENT_ID=$(gnuhealth_db_query "
    SELECT gp.id
    FROM gnuhealth_patient gp
    JOIN party_party pp ON gp.party = pp.id
    WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'
    LIMIT 1" | tr -d '[:space:]')

if [ -z "$TARGET_PATIENT_ID" ]; then
    echo "FATAL: Patient Ana Betz not found in demo database. Aborting."
    exit 1
fi
echo "Ana Betz patient_id: $TARGET_PATIENT_ID"
echo "$TARGET_PATIENT_ID" > /tmp/surgery_target_patient_id
chmod 666 /tmp/surgery_target_patient_id 2>/dev/null || true

# --- 2. Record Baseline ---
echo "Recording baseline state..."

# Check if surgery table exists, default to 0 if not
TABLE_EXISTS=$(gnuhealth_db_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'gnuhealth_surgery'" | tr -d '[:space:]')
if [ "${TABLE_EXISTS:-0}" -eq 1 ]; then
    BASELINE_SURGERY_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_surgery" | tr -d '[:space:]')
else
    echo "WARNING: gnuhealth_surgery table not found! Modules might be missing."
    BASELINE_SURGERY_MAX=0
fi

echo "Baseline surgery max ID: $BASELINE_SURGERY_MAX"
echo "$BASELINE_SURGERY_MAX" > /tmp/surgery_baseline_max
chmod 666 /tmp/surgery_baseline_max 2>/dev/null || true

# --- 3. Ensure GNU Health and Firefox are ready ---
ensure_gnuhealth_logged_in "http://localhost:8000/#menu"
sleep 5

# --- 4. Final preparations ---
# Take initial screenshot
take_screenshot /tmp/surgery_initial_state.png

echo "=== record_surgery task setup complete ==="