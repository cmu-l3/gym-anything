#!/bin/bash
echo "=== Setting up configure_isolation_ward task ==="

source /workspace/scripts/task_utils.sh
wait_for_postgres

# --- 1. Clean pre-existing target records to ensure clean state ---
echo "Cleaning any pre-existing wards or beds matching the target names..."
# Delete beds first due to foreign key constraints
gnuhealth_db_query "
    DELETE FROM gnuhealth_hospital_bed 
    WHERE name IN ('AIIR-01', 'AIIR-02')
" 2>/dev/null || true

gnuhealth_db_query "
    DELETE FROM gnuhealth_hospital_ward 
    WHERE name ILIKE '%Airborne Infection Isolation Ward%'
" 2>/dev/null || true

# --- 2. Record baseline state ---
echo "Recording baseline state..."
BASELINE_WARD_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_hospital_ward" | tr -d '[:space:]')
BASELINE_BED_MAX=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_hospital_bed" | tr -d '[:space:]')

echo "Baseline ward max ID: $BASELINE_WARD_MAX"
echo "Baseline bed max ID: $BASELINE_BED_MAX"

echo "$BASELINE_WARD_MAX" > /tmp/ward_baseline_max
echo "$BASELINE_BED_MAX" > /tmp/bed_baseline_max
chmod 666 /tmp/ward_baseline_max /tmp/bed_baseline_max 2>/dev/null || true

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt 2>/dev/null || true

# --- 3. Ensure GNU Health is running and logged in ---
echo "Ensuring GNU Health is running and logged in..."
ensure_gnuhealth_logged_in "http://localhost:8000/"

# --- 4. Prepare workspace and take initial screenshot ---
sleep 2
take_screenshot /tmp/ward_initial_state.png

echo "=== Task setup complete ==="