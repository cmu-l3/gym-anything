#!/bin/bash
echo "=== Setting up create_prescription task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh
wait_for_postgres

# 1. Record initial prescription count
INITIAL_COUNT=$(get_prescription_count)
echo "Initial prescription count: $INITIAL_COUNT"
rm -f /tmp/initial_prescription_count.txt 2>/dev/null || true
echo "$INITIAL_COUNT" > /tmp/initial_prescription_count.txt
chmod 666 /tmp/initial_prescription_count.txt 2>/dev/null || true

# 2. Verify Ana Betz patient exists in the demo DB
ANA_EXISTS=$(gnuhealth_db_query "SELECT COUNT(*) FROM gnuhealth_patient gp JOIN party_party pp ON gp.party = pp.id WHERE pp.name ILIKE '%Ana%' AND pp.lastname ILIKE '%Betz%'" | tr -d '[:space:]')
echo "Ana Betz patient found: $ANA_EXISTS"
if [ "${ANA_EXISTS:-0}" -eq 0 ]; then
    echo "WARNING: Ana Betz not found in demo database."
fi

# 3. Ensure GNU Health server is running
if ! curl -s --max-time 5 http://localhost:8000/ > /dev/null 2>&1; then
    echo "Starting GNU Health server..."
    systemctl start gnuhealth
    sleep 15
fi

# 4. Ensure logged in
ensure_gnuhealth_logged_in "http://localhost:8000/"
sleep 5

# 5. Take initial screenshot
take_screenshot /tmp/create_prescription_initial.png

echo "=== create_prescription task setup complete ==="
echo "Task: Create prescription of Metformin 500mg for Ana Betz"
echo "Navigate to Prescription module, click New, fill patient, medication, dose and save"
