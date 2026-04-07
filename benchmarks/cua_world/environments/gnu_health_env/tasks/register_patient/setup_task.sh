#!/bin/bash
echo "=== Setting up register_patient task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh
wait_for_postgres

# 1. Record initial patient count
INITIAL_COUNT=$(get_patient_count)
echo "Initial patient count: $INITIAL_COUNT"
rm -f /tmp/initial_patient_count.txt 2>/dev/null || true
echo "$INITIAL_COUNT" > /tmp/initial_patient_count.txt
chmod 666 /tmp/initial_patient_count.txt 2>/dev/null || true

# 2. Remove target patient if already exists (idempotency)
# party_party has separate 'name' (first name) and 'lastname' columns
EXISTING=$(gnuhealth_db_query "SELECT gp.id FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id WHERE pp.name ILIKE '%Marcus%' AND pp.lastname ILIKE '%Delgado%' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING" ]; then
    echo "WARNING: Patient Marcus Delgado already exists (id=$EXISTING), removing for clean test"
    PARTY_ID=$(gnuhealth_db_query "SELECT gp.party FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id WHERE pp.name ILIKE '%Marcus%' AND pp.lastname ILIKE '%Delgado%' LIMIT 1" | tr -d '[:space:]')
    gnuhealth_db_query "DELETE FROM gnuhealth_patient WHERE id = $EXISTING" 2>/dev/null || true
    if [ -n "$PARTY_ID" ]; then
        gnuhealth_db_query "DELETE FROM party_party WHERE id = $PARTY_ID" 2>/dev/null || true
    fi
fi

# 3. Ensure GNU Health server is running
if ! curl -s --max-time 5 http://localhost:8000/ > /dev/null 2>&1; then
    echo "Starting GNU Health server..."
    systemctl start gnuhealth
    sleep 15
fi

# 4. Ensure logged into GNU Health and navigate to Patient module
ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5

# 5. Take initial screenshot
take_screenshot /tmp/register_patient_initial.png

echo "=== register_patient task setup complete ==="
echo "Task: Register new patient Marcus Delgado"
echo "Navigate to Patient menu, click New Patient, fill in the form and save"
