#!/bin/bash
echo "=== Setting up configure_occupational_health_clinic task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt 2>/dev/null || true

# Wait for database to be ready
wait_for_postgres

# 1. Clean up any pre-existing records matching the expected target strings
# This ensures a clean slate and forces the agent to create them
echo "Cleaning up pre-existing target records..."
gnuhealth_db_query "DELETE FROM gnuhealth_hospital_bed WHERE name IN ('DECON-1', 'DECON-2')" 2>/dev/null || true
gnuhealth_db_query "DELETE FROM gnuhealth_hospital_ward WHERE name ILIKE '%Decontamination%'" 2>/dev/null || true
gnuhealth_db_query "DELETE FROM gnuhealth_institution WHERE name IN (SELECT id FROM party_party WHERE name ILIKE '%PetroChem%')" 2>/dev/null || true
gnuhealth_db_query "DELETE FROM party_party WHERE name ILIKE '%PetroChem%'" 2>/dev/null || true

# 2. Record maximum IDs (baselines) to prevent the agent from just renaming existing entities
echo "Recording baseline max IDs..."
BASELINE_PARTY=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM party_party" | tr -d '[:space:]')
BASELINE_INST=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_institution" | tr -d '[:space:]')
BASELINE_WARD=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_hospital_ward" | tr -d '[:space:]')
BASELINE_BED=$(gnuhealth_db_query "SELECT COALESCE(MAX(id), 0) FROM gnuhealth_hospital_bed" | tr -d '[:space:]')

echo "$BASELINE_PARTY" > /tmp/clinic_baseline_party
echo "$BASELINE_INST" > /tmp/clinic_baseline_inst
echo "$BASELINE_WARD" > /tmp/clinic_baseline_ward
echo "$BASELINE_BED" > /tmp/clinic_baseline_bed
chmod 666 /tmp/clinic_baseline_* 2>/dev/null || true

# 3. Ensure GNU Health web interface is open and logged in
echo "Ensuring GNU Health is running and logged in..."
ensure_gnuhealth_logged_in "http://localhost:8000/"

# Wait a moment for the interface to settle
sleep 3

# Take initial screenshot for reference
take_screenshot /tmp/clinic_initial_state.png

echo "=== Setup Complete ==="