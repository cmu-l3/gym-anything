#!/bin/bash
# Setup script for Create Patient Letter task

echo "=== Setting up Create Patient Letter Task ==="

source /workspace/scripts/task_utils.sh

# 1. Verify patient Maria Santos exists
# Note: Using common names from Synthea or seeding if missing
PATIENT_FNAME="Maria"
PATIENT_LNAME="Santos"

echo "Checking for patient $PATIENT_FNAME $PATIENT_LNAME..."
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='$PATIENT_FNAME' AND last_name='$PATIENT_LNAME'" || echo "0")

if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "Patient not found — seeding Maria Santos..."
    # Insert with explicit demographic_no if possible or let auto-increment
    oscar_query "INSERT IGNORE INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, city, province, postal, phone, provider_no, hin, hc_type, patient_status, lastUpdateDate) VALUES ('$PATIENT_LNAME', '$PATIENT_FNAME', 'F', '1978', '06', '12', 'Toronto', 'ON', 'M5G 1Z8', '416-555-0198', '999998', '6834729105', 'ON', 'AC', NOW());" 2>/dev/null || true
fi

# Get the demographic number
PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='$PATIENT_FNAME' AND last_name='$PATIENT_LNAME' LIMIT 1")
echo "Target Patient ID: $PATIENT_ID"
echo "$PATIENT_ID" > /tmp/task_patient_id.txt

# 2. Clean up existing letters for this patient to ensure clean verification
# (Optional: In a real persistent env we might not delete, but for a task it's safer)
echo "Cleaning up previous letters for this patient..."
oscar_query "DELETE FROM letter WHERE demographic_no='$PATIENT_ID'" 2>/dev/null || true

# 3. Record task start parameters
date +%s > /tmp/task_start_time.txt
# Record initial letter count (should be 0 after delete, but good practice)
INITIAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM letter WHERE demographic_no='$PATIENT_ID'" || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_letter_count.txt

# 4. Prepare the browser
ensure_firefox_on_oscar

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Task: Create a letter for Maria Santos (ID: $PATIENT_ID)"