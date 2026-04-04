#!/bin/bash
echo "=== Setting up Register Patient task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp (anti-gaming)
record_task_start /tmp/task_start_timestamp

# Record initial patient count
INITIAL_COUNT=$(admin_query "SELECT COUNT(*) FROM adminview" || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_patient_count
echo "Initial patient count: $INITIAL_COUNT"

# Remove any pre-existing test patient 'James Kariuki' (for re-runs)
echo "Cleaning up any pre-existing test patient..."
EXISTING_ID=$(admin_query "SELECT personid FROM adminview WHERE firstname='James' AND lastname='KARIUKI' LIMIT 1" || echo "")
if [ -n "$EXISTING_ID" ]; then
    admin_query "DELETE FROM adminprivate WHERE personid='$EXISTING_ID'" 2>/dev/null || true
    admin_query "DELETE FROM adminview WHERE personid='$EXISTING_ID'" 2>/dev/null || true
    echo "Removed existing test patient (personid=$EXISTING_ID)"
fi

# Ensure Firefox is running at OpenClinic GA
ensure_openclinic_browser "http://localhost:10088/openclinic"

# Navigate to the OpenClinic login page
navigate_to_url "http://localhost:10088/openclinic"
sleep 3

# Take screenshot for audit
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved"

echo ""
echo "=== Register Patient task ready ==="
echo ""
echo "TASK: Register a new patient with:"
echo "  First name:  James"
echo "  Last name:   Kariuki"
echo "  DOB:         1985-03-14 (March 14, 1985)"
echo "  Gender:      Male"
echo "  Address:     15 Kenyatta Avenue"
echo "  City:        Nairobi"
echo "  Country:     KE"
echo ""
echo "Login: username=4 (or 'openclinic'), password=openclinic"
echo "URL: http://localhost:10088/openclinic"
