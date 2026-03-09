#!/bin/bash
# Setup script for Register Patient task in OSCAR EMR

echo "=== Setting up Register Patient Task ==="

source /workspace/scripts/task_utils.sh

EXPECTED_FNAME="Emily"
EXPECTED_LNAME="Nakamura"

# Clean up any pre-existing test patient (for re-runs)
echo "Checking for pre-existing test patient..."
EXISTING=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='$EXPECTED_FNAME' AND last_name='$EXPECTED_LNAME' LIMIT 1")
if [ -n "$EXISTING" ]; then
    echo "Removing existing test patient (demographic_no=$EXISTING)..."
    oscar_query "DELETE FROM demographic WHERE first_name='$EXPECTED_FNAME' AND last_name='$EXPECTED_LNAME'" 2>/dev/null || true
fi

# Record timestamp for anti-gaming
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START"

# Record initial patient count (AC = active)
INITIAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE patient_status='AC'" || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_patient_count
echo "Initial patient count: $INITIAL_COUNT"

# Open Firefox on OSCAR login page
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Register Patient Task Setup Complete ==="
echo ""
echo "TASK: Register a new patient in OSCAR EMR with these details:"
echo "  First Name:   Emily"
echo "  Last Name:    Nakamura"
echo "  Date of Birth: 1991-08-14"
echo "  Sex:          Female (F)"
echo "  Address:      350 Bay Street"
echo "  City:         Toronto"
echo "  Province:     ON"
echo "  Postal Code:  M5H 2S6"
echo "  Phone:        416-555-0201"
echo "  Email:        emily.nakamura@email.ca"
echo "  Health Card:  9001234567 (ON)"
echo ""
echo "Login: oscardoc / oscar / PIN: 1117"
echo ""
