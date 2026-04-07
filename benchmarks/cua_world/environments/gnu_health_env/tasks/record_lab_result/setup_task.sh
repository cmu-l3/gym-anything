#!/bin/bash
echo "=== Setting up record_lab_result task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh
wait_for_postgres

# 1. Record initial lab request count
INITIAL_COUNT=$(get_lab_request_count)
echo "Initial lab request count: $INITIAL_COUNT"
rm -f /tmp/initial_lab_count.txt 2>/dev/null || true
echo "$INITIAL_COUNT" > /tmp/initial_lab_count.txt
chmod 666 /tmp/initial_lab_count.txt 2>/dev/null || true

# 2. Verify Ana Betz patient exists
# party_party has separate 'name' and 'lastname' columns
ANA_EXISTS=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'" | tr -d '[:space:]')
echo "Ana Betz patient found: $ANA_EXISTS"

# 3. Remove any existing HbA1c test for Ana Betz from today (idempotency)
TODAY=$(date +%Y-%m-%d)
PATIENT_ID=$(gnuhealth_db_query "SELECT gp.id FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%' LIMIT 1" | tr -d '[:space:]')
if [ -n "$PATIENT_ID" ]; then
    # gnuhealth_patient_lab_test references test_type not test text
    EXISTING_TEST=$(gnuhealth_db_query "SELECT glt.id FROM gnuhealth_patient_lab_test glt JOIN gnuhealth_lab_test_type ltt ON glt.test_type = ltt.id WHERE glt.patient_id = $PATIENT_ID AND (LOWER(ltt.name) LIKE '%hba1c%' OR LOWER(ltt.code) LIKE '%hba1c%') LIMIT 1" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$EXISTING_TEST" ]; then
        echo "Removing existing HbA1c test (id=$EXISTING_TEST)"
        gnuhealth_db_query "DELETE FROM gnuhealth_patient_lab_test WHERE id = $EXISTING_TEST" 2>/dev/null || true
    fi
fi

# 4. Ensure GNU Health server is running
if ! curl -s --max-time 5 http://localhost:8000/ > /dev/null 2>&1; then
    echo "Starting GNU Health server..."
    systemctl start gnuhealth
    sleep 15
fi

# 5. Ensure logged in and navigate to GNU Health
ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5

# 6. Take initial screenshot
take_screenshot /tmp/record_lab_result_initial.png

echo "=== record_lab_result task setup complete ==="
echo "Task: Create HbA1c lab test and record result 7.2% for Ana Betz"
echo "Navigate to Laboratory module, create new test request, enter result and validate"
