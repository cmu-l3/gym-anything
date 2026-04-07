#!/bin/bash
echo "=== Setting up create_health_evaluation task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for PostgreSQL
wait_for_postgres 60

# Record initial evaluation count
INITIAL_EVAL_COUNT=$(gnuhealth_count "gnuhealth_patient_evaluation" 2>/dev/null || echo "0")
echo "$INITIAL_EVAL_COUNT" > /tmp/initial_eval_count.txt
echo "Initial evaluation count: $INITIAL_EVAL_COUNT"

# Verify Ana Betz exists in the database
ANA_PATIENT_ID=$(get_patient_id_by_name "Ana" "Betz")
if [ -z "$ANA_PATIENT_ID" ]; then
    echo "ERROR: Patient Ana Betz not found in demo database! Using fallback..."
    # Try broader search
    ANA_PATIENT_ID=$(gnuhealth_db_query "SELECT gp.id FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id WHERE pp.name ILIKE '%ana%' LIMIT 1" | tr -d '[:space:]')
fi
echo "$ANA_PATIENT_ID" > /tmp/ana_patient_id.txt
echo "Ana Betz patient ID: $ANA_PATIENT_ID"

# Ensure GNU Health server is running
if ! curl -s --max-time 5 "http://localhost:8000/" > /dev/null 2>&1; then
    echo "Starting GNU Health server..."
    systemctl start gnuhealth || true
    sleep 10
fi

# Ensure Firefox is running and logged in
ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5

# Focus and maximize Firefox
focus_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="